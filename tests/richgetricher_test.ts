
import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v0.6.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test
({
    name: "Ensure that lobbies and games can be created.",
    async fn(chain: Chain, accounts: Map<string, Account>) 
    {
        let wallet_deployer = accounts.get("deployer");
        let wallet_1 = accounts.get("wallet_1")!;
        let wallet_2 = accounts.get("wallet_2")!;
        let wallet_3 = accounts.get("wallet_3")!;
        let block = chain.mineBlock
        ([
            /*0:*/ Tx.contractCall("richgetricher", "get-lobby", [], wallet_1.address),
            /*1:*/ Tx.contractCall("richgetricher", "create-lobby", [types.ascii("My lobby name"), types.uint(10)], wallet_1.address),
            /*2:*/ Tx.contractCall("richgetricher", "get-lobby", [], wallet_1.address),
            /*3:*/ Tx.contractCall("richgetricher", "create-game", [types.ascii("My game name"), types.uint(50), types.uint(180)], wallet_2.address),
            /*4:*/ Tx.contractCall("richgetricher", "get-lobby", [], wallet_3.address),
        ]);
        assertEquals(block.height, 2);
        block.receipts[0].result
            .expectErr();
        block.receipts[1].result
            .expectOk()
            .expectAscii("My lobby name");
        block.receipts[2].result
            .expectErr();
        block.receipts[3].result
            .expectOk()
            .expectUint(1);
        block.receipts[4].result
            .expectOk()
            .expectList()
            .map((e: String) => e.expectTuple());
    },
});

Clarinet.test
({
    name: "Ensure that games can be played.",
    async fn(chain: Chain, accounts: Map<string, Account>) 
    {
        let wallet_deployer = accounts.get("deployer");
        let wallet_1 = accounts.get("wallet_1")!;
        let wallet_2 = accounts.get("wallet_2")!;
        let wallet_3 = accounts.get("wallet_3")!;
        let wallet_4 = accounts.get("wallet_4")!;
        let block = chain.mineBlock
        ([
            /*0:*/ Tx.contractCall("richgetricher", "create-lobby", [types.ascii("My lobby name"), types.uint(50)], wallet_1.address),
            /*1:*/ Tx.contractCall("richgetricher", "create-game", [types.ascii("My game name"), types.uint(100), types.uint(1)], wallet_4.address),
            /*2:*/ Tx.contractCall("richgetricher", "create-game", [types.ascii("My second game name"), types.uint(500), types.uint(1)], wallet_4.address),
            /*3:*/ Tx.contractCall("richgetricher", "get-lobby", [], wallet_2.address),
            /*4:*/ Tx.contractCall("richgetricher", "get-game", [types.uint(1)], wallet_2.address),
            /*5:*/ Tx.contractCall("richgetricher", "participate", [types.uint(1), types.uint(1000), types.ascii("I'm the leader now!")], wallet_2.address),
            /*6:*/ Tx.contractCall("richgetricher", "get-game", [types.uint(1)], wallet_3.address),
            /*7:*/ Tx.contractCall("richgetricher", "participate", [types.uint(1), types.uint(1001), types.ascii("No! I'm the leader now!")], wallet_3.address),
            /*8:*/ Tx.contractCall("richgetricher", "get-game", [types.uint(1)], wallet_2.address),
        ]);
        assertEquals(block.height, 2);
        block.receipts[0].result
            .expectOk()
            .expectAscii("My lobby name");
        block.receipts[1].result
            .expectOk()
            .expectUint(1);
        block.receipts[2].result
            .expectOk()
            .expectUint(2);
        block.receipts[3].result
            .expectOk()
            .expectList()
            .map((e: String) => e.expectTuple());
        block.receipts[4].result
            .expectOk()
            .expectTuple();
        block.receipts[5].result
            .expectOk()
            .expectBool(true);
        console.log(`\r\n\r\n${block.height}: ${block.receipts[6].result}`)
        block.receipts[6].result
            .expectOk()
            .expectTuple();
        block.receipts[7].result
            .expectOk()
            .expectBool(true);
        console.log(`\r\n${block.height}: ${block.receipts[8].result}`)
        block.receipts[8].result
            .expectOk()
            .expectTuple();

        block = chain.mineBlock
        ([
            /*0:*/ Tx.contractCall("richgetricher", "get-game", [types.uint(1)], wallet_2.address),
            /*1:*/ Tx.contractCall("richgetricher", "participate", [types.uint(1), types.uint(1000), types.ascii("I'm the leader again!")], wallet_2.address),
        ]);
        assertEquals(block.height, 3);
        block.receipts[0].result
            .expectOk()
            .expectTuple();
        console.log(`\r\n\r\n${block.height}: ${block.receipts[0].result}`)
        block.receipts[1].result
            .expectOk();

        block = chain.mineBlock
        ([
            /*0:*/ Tx.contractCall("richgetricher", "get-game", [types.uint(1)], wallet_2.address),
            /*1:*/ Tx.contractCall("richgetricher", "participate", [types.uint(1), types.uint(1000), types.ascii("No! I'm the leader again!")], wallet_3.address),
        ]);
        assertEquals(block.height, 4);
        block.receipts[0].result
            .expectOk()
            .expectTuple();
        console.log(`\r\n\r\n${block.height}: ${block.receipts[0].result}`)
        block.receipts[1].result
            .expectErr();

        let result = chain.getAssetsMaps();
        console.log(result);
        console.log(`Wallet_1 ${result.assets["STX"][wallet_1.address]}`);
        console.log(`Wallet_2 ${result.assets["STX"][wallet_2.address]}`);
        console.log(`Wallet_3 ${result.assets["STX"][wallet_3.address]}`);
        console.log(`Wallet_4 ${result.assets["STX"][wallet_4.address]}`);
    },
});