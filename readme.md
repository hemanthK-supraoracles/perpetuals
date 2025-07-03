## Contract description
- The contract is a perpetual contract, which means it does not have an expiration date.

- Initially we are using custom "MyUSDC" coin as a collateral for all users
  we can have many pairs of <Asset type, Collateral type> for a user.
  For actual production grade contract, we need to handle all possible Asset types and Collateral types.

- Market represents data structure for a single asset type.

- Users can open / close positions for an Asset type. When user closes his position we have to caluculate his Final
 Profit and Loss (PnL) balance and transfer it to his wallet. 
 
?? We have to decide whether we transfer it in single asset type or both Asset and Collateral type

- Leverage lets user bet of higher amount than his actual balance. It is calculated as Leverage = (Asset size Value / Collateral Value) 
?? We must decide what should be highest leverage a user can have
?? Does it differ with different asset types?


- All the collected collateral is stores in UserCollateral struct for each user.

## Theory

FUNDING RATE THEORY: 
Spot price definition: Actual price of asset in reality
Contract price / Perpetual price: Trading price of asset in the contract.

- The funding rate is a mechanism that ensures that the price of the perpetual futures contract stays close to the spot price of the underlying asset. It is a periodic payment exchanged between the buyers (longs) and sellers (shorts) of the contract, based on the difference between the contract price and the spot price, similar in some ways to a swap contract.

The funding rate can be positive or negative, depending on market conditions. When the funding rate is positive, it means that the contract price is higher than the spot price, also known as contango. In this case, the longs pay the shorts the funding amount. When the funding rate is negative, it means that the contract price is lower than the spot price, known as backwardation. In this case, the shorts pay the longs the funding amount.

The funding rate is usually calculated based on a combination of the perpetual contract’s price, the spot price, and an interest rate component. The interest rate reflects the cost of borrowing or lending the underlying asset, while the premium index reflects the difference between the contract price and the spot price.

The formula may also include a cap and a floor to limit the maximum and minimum funding rate possible. It is important to note that the exact formula can vary depending on the specific exchange or platform you are using.

?? We have to decide how often do we run funding rate mechanism 
?? We have to decide how to calculate funding rate


## Features to be decided