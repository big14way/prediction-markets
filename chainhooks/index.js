require('dotenv').config();
const { Chainhook } = require('@hirosystems/chainhook-client');

const DEPLOYER_ADDRESS = process.env.DEPLOYER_ADDRESS || 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM';
const MARKET_CONTRACT = `${DEPLOYER_ADDRESS}.market-manager`;
const ORACLE_CONTRACT = `${DEPLOYER_ADDRESS}.oracle-registry`;
const TOKEN_CONTRACT = `${DEPLOYER_ADDRESS}.market-token`;

const chainhook = new Chainhook({
  baseUrl: process.env.CHAINHOOK_NODE_URL || 'http://localhost:20456',
});

async function monitorPredictionMarketEvents() {
  console.log('Monitoring Prediction Market events...');
  console.log('Market Contract:', MARKET_CONTRACT);
  console.log('Oracle Contract:', ORACLE_CONTRACT);
  console.log('Token Contract:', TOKEN_CONTRACT);

  const marketCreatedHook = {
    uuid: 'prediction-market-created',
    name: 'Market Created',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'print_event',
          contract_identifier: MARKET_CONTRACT,
          contains: 'Market'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/market-created',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const betPlacedHook = {
    uuid: 'prediction-bet-placed',
    name: 'Bet Placed',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'contract_call',
          contract_identifier: MARKET_CONTRACT,
          method: 'place-bet'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/bet-placed',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const oracleReportHook = {
    uuid: 'prediction-oracle-report',
    name: 'Oracle Report',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'print_event',
          contract_identifier: ORACLE_CONTRACT,
          contains: 'resolution'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/oracle-report',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const marketResolvedHook = {
    uuid: 'prediction-market-resolved',
    name: 'Market Resolved',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'print_event',
          contract_identifier: MARKET_CONTRACT,
          contains: 'Resolved'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/market-resolved',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const payoutHook = {
    uuid: 'prediction-payout',
    name: 'Payout Claimed',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'contract_call',
          contract_identifier: MARKET_CONTRACT,
          method: 'claim-winnings'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/payout',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  try {
    await chainhook.createPredicate(marketCreatedHook);
    console.log('Registered: Market Created hook');

    await chainhook.createPredicate(betPlacedHook);
    console.log('Registered: Bet Placed hook');

    await chainhook.createPredicate(oracleReportHook);
    console.log('Registered: Oracle Report hook');

    await chainhook.createPredicate(marketResolvedHook);
    console.log('Registered: Market Resolved hook');

    await chainhook.createPredicate(payoutHook);
    console.log('Registered: Payout hook');

    console.log('\nAll hooks registered successfully!');
  } catch (error) {
    console.error('Error registering hooks:', error);
  }
}

function handleEvent(event) {
  console.log('Received event:', JSON.stringify(event, null, 2));
}

monitorPredictionMarketEvents().catch(console.error);

module.exports = { handleEvent };
