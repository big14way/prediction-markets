import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

const ONE_DAY = 86400;
const ONE_WEEK = 604800;

Clarinet.test({
    name: "Can verify an oracle",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('market-manager', 'verify-oracle', [
                types.principal(`${deployer.address}.oracle-registry`),
                types.ascii("Test Oracle")
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
    }
});

Clarinet.test({
    name: "Only admin can verify oracles",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('market-manager', 'verify-oracle', [
                types.principal(`${deployer.address}.oracle-registry`),
                types.ascii("Fake Oracle")
            ], user.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(16001); // ERR_NOT_AUTHORIZED
    }
});

Clarinet.test({
    name: "Can create market with verified oracle",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const creator = accounts.get('wallet_1')!;
        
        const currentTime = chain.callReadOnlyFn('market-manager', 'get-current-time', [], creator.address);
        const now = Number(currentTime.result.replace('u', ''));
        
        // First verify the oracle
        chain.mineBlock([
            Tx.contractCall('market-manager', 'verify-oracle', [
                types.principal(`${deployer.address}.oracle-registry`),
                types.ascii("Test Oracle")
            ], deployer.address)
        ]);
        
        // Create market
        let block = chain.mineBlock([
            Tx.contractCall('market-manager', 'create-market', [
                types.ascii("Will BTC hit $100k in 2025?"),
                types.list([types.ascii("Yes"), types.ascii("No")]),
                types.uint(now + ONE_WEEK),
                types.principal(`${deployer.address}.oracle-registry`)
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Cannot create market with unverified oracle",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const creator = accounts.get('wallet_1')!;
        
        const currentTime = chain.callReadOnlyFn('market-manager', 'get-current-time', [], creator.address);
        const now = Number(currentTime.result.replace('u', ''));
        
        // Try to create market without verifying oracle
        let block = chain.mineBlock([
            Tx.contractCall('market-manager', 'create-market', [
                types.ascii("Unverified market"),
                types.list([types.ascii("Yes"), types.ascii("No")]),
                types.uint(now + ONE_WEEK),
                types.principal(`${deployer.address}.oracle-registry`)
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(16008); // ERR_ORACLE_NOT_VERIFIED
    }
});

Clarinet.test({
    name: "Market needs at least 2 outcomes",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const creator = accounts.get('wallet_1')!;
        
        const currentTime = chain.callReadOnlyFn('market-manager', 'get-current-time', [], creator.address);
        const now = Number(currentTime.result.replace('u', ''));
        
        // Verify oracle first
        chain.mineBlock([
            Tx.contractCall('market-manager', 'verify-oracle', [
                types.principal(`${deployer.address}.oracle-registry`),
                types.ascii("Test Oracle")
            ], deployer.address)
        ]);
        
        // Try with only 1 outcome
        let block = chain.mineBlock([
            Tx.contractCall('market-manager', 'create-market', [
                types.ascii("Single outcome market"),
                types.list([types.ascii("Only Option")]),
                types.uint(now + ONE_WEEK),
                types.principal(`${deployer.address}.oracle-registry`)
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(16005); // ERR_INVALID_OUTCOME
    }
});

Clarinet.test({
    name: "Get protocol stats",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let stats = chain.callReadOnlyFn(
            'market-manager',
            'get-protocol-stats',
            [],
            user.address
        );
        
        const data = stats.result.expectTuple();
        assertEquals(data['total-markets'], types.uint(0));
        assertEquals(data['total-volume'], types.uint(0));
    }
});

Clarinet.test({
    name: "Can calculate potential payout",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user = accounts.get('wallet_1')!;
        
        const currentTime = chain.callReadOnlyFn('market-manager', 'get-current-time', [], user.address);
        const now = Number(currentTime.result.replace('u', ''));
        
        // Setup market
        chain.mineBlock([
            Tx.contractCall('market-manager', 'verify-oracle', [
                types.principal(`${deployer.address}.oracle-registry`),
                types.ascii("Test Oracle")
            ], deployer.address),
            Tx.contractCall('market-manager', 'create-market', [
                types.ascii("Test Market"),
                types.list([types.ascii("Yes"), types.ascii("No")]),
                types.uint(now + ONE_WEEK),
                types.principal(`${deployer.address}.oracle-registry`)
            ], user.address)
        ]);
        
        // Calculate payout for first bet
        let payout = chain.callReadOnlyFn(
            'market-manager',
            'calculate-payout',
            [
                types.uint(1),
                types.uint(0), // Yes outcome
                types.uint(100000000) // 100 STX bet
            ],
            user.address
        );
        
        // First bet should get full pot
        assertEquals(payout.result, 'u100000000');
    }
});

// Oracle Registry Tests

Clarinet.test({
    name: "Can initialize oracle types",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('oracle-registry', 'initialize-types', [], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
        
        let typeName = chain.callReadOnlyFn(
            'oracle-registry',
            'get-type-name',
            [types.uint(0)],
            deployer.address
        );
        
        typeName.result.expectAscii("Sports");
    }
});

Clarinet.test({
    name: "Can register oracle",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('oracle-registry', 'register-oracle', [
                types.principal(`${deployer.address}.market-manager`),
                types.ascii("Sports Oracle"),
                types.uint(0), // ORACLE_TYPE_SPORTS
                types.uint(0)  // No stake
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Can calculate reliability score",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        // Register oracle
        chain.mineBlock([
            Tx.contractCall('oracle-registry', 'register-oracle', [
                types.principal(`${deployer.address}.market-manager`),
                types.ascii("Test Oracle"),
                types.uint(0),
                types.uint(0)
            ], deployer.address)
        ]);
        
        // New oracle should have 100% reliability
        let reliability = chain.callReadOnlyFn(
            'oracle-registry',
            'get-reliability-score',
            [types.uint(1)],
            deployer.address
        );
        
        assertEquals(reliability.result, 'u10000'); // 100% in basis points
    }
});
