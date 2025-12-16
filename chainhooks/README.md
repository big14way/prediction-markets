# Prediction Market - Chainhooks Integration

Monitor prediction market events in real-time using Hiro Chainhooks.

## Monitored Events

- **Market Creation**: New prediction markets created
- **Bets**: Bet placements on market outcomes
- **Oracle Reports**: Oracle resolution submissions
- **Market Resolutions**: Markets resolved with winning outcomes
- **Payouts**: Winners claiming their payouts

## Setup

```bash
npm install
cp .env.example .env
# Configure your .env file
npm start
```

## Contract Addresses

- Market Manager: `${DEPLOYER_ADDRESS}.market-manager`
- Oracle Registry: `${DEPLOYER_ADDRESS}.oracle-registry`
- Market Token: `${DEPLOYER_ADDRESS}.market-token`

See [Chainhooks Documentation](https://docs.hiro.so/chainhooks) for more details.
