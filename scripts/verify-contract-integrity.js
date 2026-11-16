const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const BASELINE_PATH = path.join(ROOT, '.ci', 'contract-baseline.json');
const GAS_REPORT_PATH = path.join(ROOT, 'gasReporterOutput.json');
const DEPLOYED_BYTECODE_LIMIT = 23_616;

const PRODUCTION_CONTRACTS = [
    ['contracts/AllPayAuction.sol', 'AllPayAuction'],
    ['contracts/EnglishAuction.sol', 'EnglishAuction'],
    ['contracts/ExponentialReverseDutchAuction.sol', 'ExponentialReverseDutchAuction'],
    ['contracts/LinearReverseDutchAuction.sol', 'LinearReverseDutchAuction'],
    ['contracts/LogarithmicReverseDutchAuction.sol', 'LogarithmicReverseDutchAuction'],
    ['contracts/ProtocolParameters.sol', 'ProtocolParameters'],
    ['contracts/VickreyAuction.sol', 'VickreyAuction'],
];

const PRODUCTION_NAMES = new Set(PRODUCTION_CONTRACTS.map(([, name]) => name));

function soliditySources(directory) {
    const sources = [];

    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const entryPath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
            if (!['abstract', 'mocks'].includes(entry.name)) {
                sources.push(...soliditySources(entryPath));
            }
        } else if (entry.name.endsWith('.sol')) {
            sources.push(path.relative(ROOT, entryPath).split(path.sep).join('/'));
        }
    }

    return sources;
}

function discoverDeployableContracts() {
    const contracts = [];

    for (const sourceName of soliditySources(path.join(ROOT, 'contracts'))) {
        const artifactDirectory = path.join(ROOT, 'artifacts', sourceName);
        if (!fs.existsSync(artifactDirectory)) {
            throw new Error(`Missing artifacts for ${sourceName}; run \`pnpm compile\``);
        }

        for (const fileName of fs.readdirSync(artifactDirectory)) {
            if (!fileName.endsWith('.json') || fileName.endsWith('.dbg.json')) continue;
            const artifact = readJson(path.join(artifactDirectory, fileName), 'Missing Hardhat artifact');
            if (artifact.deployedBytecode && artifact.deployedBytecode !== '0x') {
                contracts.push([sourceName, artifact.contractName]);
            }
        }
    }

    return contracts.sort(([leftSource, leftName], [rightSource, rightName]) => `${leftSource}:${leftName}`.localeCompare(`${rightSource}:${rightName}`));
}

function verifyProductionContractList() {
    const expected = new Set(PRODUCTION_CONTRACTS.map(([source, name]) => `${source}:${name}`));
    const discovered = new Set(discoverDeployableContracts().map(([source, name]) => `${source}:${name}`));

    for (const contract of discovered) {
        if (!expected.has(contract)) {
            throw new Error(`New deployable contract is not tracked by the integrity checker: ${contract}`);
        }
    }
    for (const contract of expected) {
        if (!discovered.has(contract)) {
            throw new Error(`Tracked production contract is no longer deployable: ${contract}`);
        }
    }
}

function readJson(filePath, hint) {
    if (!fs.existsSync(filePath)) {
        throw new Error(`${hint}: ${path.relative(ROOT, filePath)}`);
    }
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function stableValue(value) {
    if (Array.isArray(value)) {
        return value.map(stableValue);
    }
    if (value && typeof value === 'object') {
        return Object.fromEntries(
            Object.keys(value)
                .sort()
                .map((key) => [key, stableValue(value[key])]),
        );
    }
    return value;
}

function stableStringify(value) {
    return JSON.stringify(stableValue(value));
}

function sha256(value) {
    const input = Buffer.isBuffer(value) ? value : Buffer.from(stableStringify(value));
    return crypto.createHash('sha256').update(input).digest('hex');
}

function canonicalAbi(abi) {
    return abi.map(stableValue).sort((left, right) => stableStringify(left).localeCompare(stableStringify(right)));
}

function normalizeTypeId(typeId) {
    return typeId.replace(/t_(struct|enum|contract|userDefinedValueType)\(([^)]*)\)\d+/g, 't_$1($2)');
}

function normalizeStorageValue(value, key = '') {
    if (Array.isArray(value)) {
        return value.map((entry) => normalizeStorageValue(entry));
    }
    if (value && typeof value === 'object') {
        return Object.fromEntries(
            Object.entries(value)
                .filter(([entryKey]) => entryKey !== 'astId')
                .map(([entryKey, entryValue]) => [entryKey, normalizeStorageValue(entryValue, entryKey)]),
        );
    }
    if (typeof value === 'string' && ['base', 'key', 'type', 'value'].includes(key)) {
        return normalizeTypeId(value);
    }
    return value;
}

function canonicalStorageLayout(layout) {
    const types = {};

    for (const [typeId, definition] of Object.entries(layout.types)) {
        const normalizedId = normalizeTypeId(typeId);
        const normalizedDefinition = normalizeStorageValue(definition);

        if (types[normalizedId] && stableStringify(types[normalizedId]) !== stableStringify(normalizedDefinition)) {
            throw new Error(`Storage layout type collision after normalization: ${normalizedId}`);
        }
        types[normalizedId] = normalizedDefinition;
    }

    return {
        storage: normalizeStorageValue(layout.storage),
        types,
    };
}

function bytecodeBuffer(bytecode) {
    const hex = bytecode.startsWith('0x') ? bytecode.slice(2) : bytecode;
    return Buffer.from(hex, 'hex');
}

function stripSolidityMetadata(bytecode) {
    const bytes = bytecodeBuffer(bytecode);
    if (bytes.length < 2) return bytes;

    const metadataLength = bytes.readUInt16BE(bytes.length - 2);
    const metadataStart = bytes.length - metadataLength - 2;
    return metadataStart >= 0 ? bytes.subarray(0, metadataStart) : bytes;
}

function contractBuild(sourceName, contractName) {
    const artifactDirectory = path.join(ROOT, 'artifacts', sourceName);
    const artifact = readJson(path.join(artifactDirectory, `${contractName}.json`), 'Missing Hardhat artifact; run `pnpm compile`');
    const debug = readJson(path.join(artifactDirectory, `${contractName}.dbg.json`), 'Missing Hardhat debug artifact; run `pnpm compile`');
    const buildInfo = readJson(path.resolve(artifactDirectory, debug.buildInfo), 'Missing Hardhat build info; run `pnpm compile`');
    const compilerOutput = buildInfo.output?.contracts?.[sourceName]?.[contractName];

    if (!compilerOutput?.storageLayout) {
        throw new Error(`Storage layout was not emitted for ${sourceName}:${contractName}`);
    }

    return { artifact, buildInfo, compilerOutput };
}

function compilerProfile(buildInfo) {
    const settings = buildInfo.input.settings;
    return {
        solc: buildInfo.solcLongVersion ?? buildInfo.solcVersion,
        optimizer: settings.optimizer,
        viaIR: settings.viaIR === true,
        evmVersion: settings.evmVersion,
    };
}

function collectContracts() {
    verifyProductionContractList();

    const contracts = {};
    let compiler;

    for (const [sourceName, contractName] of PRODUCTION_CONTRACTS) {
        const key = `${sourceName}:${contractName}`;
        const { artifact, buildInfo, compilerOutput } = contractBuild(sourceName, contractName);
        const profile = compilerProfile(buildInfo);

        if (compiler && stableStringify(compiler) !== stableStringify(profile)) {
            throw new Error(`Production contracts use inconsistent compiler settings at ${key}`);
        }
        compiler = profile;

        const deployedBytecode = bytecodeBuffer(artifact.deployedBytecode);
        if (deployedBytecode.length > DEPLOYED_BYTECODE_LIMIT) {
            throw new Error(`${key} is ${deployedBytecode.length} bytes, above the ${DEPLOYED_BYTECODE_LIMIT}-byte deployment limit`);
        }

        contracts[key] = {
            abiHash: sha256(canonicalAbi(artifact.abi)),
            runtimeCodeHash: sha256(stripSolidityMetadata(artifact.deployedBytecode)),
            storageLayoutHash: sha256(canonicalStorageLayout(compilerOutput.storageLayout)),
            deployedBytecodeBytes: deployedBytecode.length,
        };
    }

    return { compiler, contracts };
}

function maxGas(values, label) {
    if (!Array.isArray(values) || values.length === 0) {
        throw new Error(`Gas report has no measurements for ${label}`);
    }
    return Math.max(...values.map(Number));
}

function sortedObject(entries) {
    return Object.fromEntries(entries.sort(([left], [right]) => left.localeCompare(right)));
}

function collectGas() {
    const report = readJson(GAS_REPORT_PATH, 'Missing gas report; run `CI=true REPORT_GAS=true pnpm test` first');
    const methods = new Map();
    const deployments = new Map();

    for (const metric of Object.values(report.info?.methods ?? {})) {
        if (!PRODUCTION_NAMES.has(metric.contract) || !Array.isArray(metric.gasData) || metric.gasData.length === 0) continue;
        const key = `${metric.contract}.${metric.method}.${metric.key}`;
        const measured = maxGas(metric.gasData, key);
        methods.set(key, Math.max(methods.get(key) ?? 0, measured));
    }

    for (const metric of report.info?.deployments ?? []) {
        if (!PRODUCTION_NAMES.has(metric.name) || !Array.isArray(metric.gasData) || metric.gasData.length === 0) continue;
        const measured = maxGas(metric.gasData, metric.name);
        deployments.set(metric.name, Math.max(deployments.get(metric.name) ?? 0, measured));
    }

    if (methods.size === 0 || deployments.size === 0) {
        throw new Error('Gas report contains no production contract measurements');
    }

    return {
        methods: sortedObject([...methods.entries()]),
        deployments: sortedObject([...deployments.entries()]),
    };
}

function collectCurrentState() {
    const { compiler, contracts } = collectContracts();
    return {
        schemaVersion: 1,
        deployedBytecodeLimit: DEPLOYED_BYTECODE_LIMIT,
        compiler,
        contracts,
        gas: collectGas(),
    };
}

function compareGas(errors, label, baseline, current) {
    for (const [key, currentGas] of Object.entries(current)) {
        if (baseline[key] === undefined) {
            errors.push(`${label} has a new unreviewed metric: ${key} (${currentGas} gas)`);
        } else if (currentGas > baseline[key]) {
            errors.push(`${label} gas regression for ${key}: ${currentGas} > ${baseline[key]}`);
        }
    }

    for (const key of Object.keys(baseline)) {
        if (current[key] === undefined) {
            errors.push(`${label} metric disappeared from test coverage: ${key}`);
        }
    }
}

function verifyBaseline(baseline, current) {
    const errors = [];

    if (baseline.schemaVersion !== 1) {
        errors.push(`Unsupported baseline schema version: ${baseline.schemaVersion}`);
    }
    if (baseline.deployedBytecodeLimit !== DEPLOYED_BYTECODE_LIMIT) {
        errors.push('The deployed bytecode limit changed without a baseline update');
    }
    if (stableStringify(baseline.compiler) !== stableStringify(current.compiler)) {
        errors.push('Compiler or optimizer settings changed');
    }

    for (const [key, contract] of Object.entries(current.contracts)) {
        const expected = baseline.contracts[key];
        if (!expected) {
            errors.push(`New production contract is missing from the baseline: ${key}`);
            continue;
        }

        for (const field of ['abiHash', 'runtimeCodeHash', 'storageLayoutHash']) {
            if (contract[field] !== expected[field]) {
                errors.push(`${field} changed for ${key}`);
            }
        }

        if (contract.deployedBytecodeBytes > expected.deployedBytecodeBytes) {
            errors.push(`${key} deployed bytecode grew from ${expected.deployedBytecodeBytes} to ${contract.deployedBytecodeBytes} bytes`);
        }
    }

    for (const key of Object.keys(baseline.contracts)) {
        if (!current.contracts[key]) {
            errors.push(`Baseline contract is no longer compiled: ${key}`);
        }
    }

    compareGas(errors, 'Method', baseline.gas.methods, current.gas.methods);
    compareGas(errors, 'Deployment', baseline.gas.deployments, current.gas.deployments);

    if (errors.length > 0) {
        console.error('Contract integrity verification failed:');
        for (const message of errors) console.error(`- ${message}`);
        console.error('\nFor intentional changes, review the diff and run `pnpm integrity:update`.');
        process.exitCode = 1;
        return;
    }

    console.log(`Contract integrity verified for ${Object.keys(current.contracts).length} contracts.`);
}

function main() {
    const current = collectCurrentState();

    if (process.argv.includes('--update')) {
        fs.mkdirSync(path.dirname(BASELINE_PATH), { recursive: true });
        fs.writeFileSync(BASELINE_PATH, `${JSON.stringify(current, null, 2)}\n`);
        console.log(`Updated ${path.relative(ROOT, BASELINE_PATH)}.`);
        return;
    }

    const baseline = readJson(BASELINE_PATH, 'Missing contract baseline; run `pnpm integrity:update` after reviewing current artifacts');
    verifyBaseline(baseline, current);
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
