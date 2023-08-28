// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/**
 * @dev Repurposed ExponentialCurve from the Sudoswap V2 repo for use with FriendShares:
 *      https://github.com/sudoswap/lssvm2/blob/main/src/bonding-curves/ExponentialCurve.sol
 *
 * @author 0xmons, boredGenius, 0xCygaar
 * @notice Bonding curve logic for an exponential curve, where each buy/sell changes spot price by multiplying/dividing delta
 */
contract ExponentialCurve {
    using FixedPointMathLib for uint256;

    /**
     * @notice Minimum price to prevent numerical issues
     */
    uint256 private constant _MIN_PRICE = 1000000 wei;

    // Spot price for the first share of a user purchased.
    uint128 private constant _INITIAL_PRICE = 0.001 ether;

    // Price changes by 0.25% for each share bought or sold.
    uint128 private constant _DELTA = 10025e14;

    // 1.5% fee goes to the shares user.
    // FixedPointMathLib.WAD.mulDiv(15, 1000).
    uint256 private constant _USER_FEE_PERCENT = 15e15;

    // 0.5% fee goes to the protocol.
    // FixedPointMathLib.WAD.mulDiv(5, 1000).
    uint256 private constant _PROTOCOL_FEE_PERCENT = 5e15;

    error InvalidNumItems();
    error SpotPriceOverflow();
    error SpotPriceUnderflow();

    function getBuyInfo(
        uint128 spotPrice,
        uint256 numItems
    )
        public
        pure
        returns (
            uint128 newSpotPrice,
            uint256 inputValue,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        // We only calculate changes for buying 1 or more items
        if (numItems == 0) revert InvalidNumItems();

        if (spotPrice == 0) spotPrice = _INITIAL_PRICE;

        uint256 deltaPowN = uint256(_DELTA).rpow(
            numItems,
            FixedPointMathLib.WAD
        );

        // For an exponential curve, the spot price is multiplied by delta for each item bought
        uint256 newSpotPrice_ = uint256(spotPrice).mulWadUp(deltaPowN);

        if (newSpotPrice_ > type(uint128).max) revert SpotPriceOverflow();

        newSpotPrice = uint128(newSpotPrice_);

        // Spot price is assumed to be the instant sell price. To avoid arbitraging LPs, we adjust the buy price upwards.
        // If spot price for buy and sell were the same, then someone could buy 1 item and then sell for immediate profit.
        // EX: Let S be spot price. Then buying 1 item costs S ETH, now new spot price is (S * delta).
        // The same person could then sell for (S * delta) ETH, netting them delta ETH profit.
        // If spot price for buy and sell differ by delta, then buying costs (S * delta) ETH.
        // The new spot price would become (S * delta), so selling would also yield (S * delta) ETH.
        uint256 buySpotPrice = uint256(spotPrice).mulWadUp(_DELTA);

        // If the user buys n items, then the total cost is equal to:
        // buySpotPrice + (delta * buySpotPrice) + (delta^2 * buySpotPrice) + ... (delta^(numItems - 1) * buySpotPrice)
        // This is equal to buySpotPrice * (delta^n - 1) / (delta - 1)
        inputValue = buySpotPrice.mulWadUp(
            (deltaPowN - FixedPointMathLib.WAD).divWadUp(
                _DELTA - FixedPointMathLib.WAD
            )
        );

        // Account for the protocol and user fees, a flat percentage of the buy amount
        protocolFee = inputValue.mulWadUp(_PROTOCOL_FEE_PERCENT);
        userFee = inputValue.mulWadUp(_USER_FEE_PERCENT);

        // Add the protocol and user fees to the required input amount
        inputValue += protocolFee + userFee;
    }

    /**
     * If newSpotPrice is less than _MIN_PRICE, newSpotPrice is set to _MIN_PRICE instead.
     * This is to prevent the spot price from ever becoming 0, which would decouple the price
     * from the bonding curve (since 0 * delta is still 0)
     */
    function getSellInfo(
        uint128 spotPrice,
        uint256 numItems
    )
        public
        pure
        returns (
            uint128 newSpotPrice,
            uint256 outputValue,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        // We only calculate changes for buying 1 or more items
        if (numItems == 0) revert InvalidNumItems();

        uint256 invDelta = FixedPointMathLib.WAD.divWad(_DELTA);
        uint256 invDeltaPowN = invDelta.rpow(numItems, FixedPointMathLib.WAD);

        // For an exponential curve, the spot price is divided by delta for each item sold
        // safe to convert newSpotPrice directly into uint128 since we know newSpotPrice <= spotPrice
        // and spotPrice <= type(uint128).max
        newSpotPrice = uint128(uint256(spotPrice).mulWad(invDeltaPowN));

        // Prevent getting stuck in a minimal price
        if (newSpotPrice < _MIN_PRICE) revert SpotPriceUnderflow();

        // If the user sells n items, then the total revenue is equal to:
        // spotPrice + ((1 / delta) * spotPrice) + ((1 / delta)^2 * spotPrice) + ... ((1 / delta)^(numItems - 1) * spotPrice)
        // This is equal to spotPrice * (1 - (1 / delta^n)) / (1 - (1 / delta))
        outputValue = uint256(spotPrice).mulWad(
            (FixedPointMathLib.WAD - invDeltaPowN).divWad(
                FixedPointMathLib.WAD - invDelta
            )
        );

        // Account for the protocol and user fees, a flat percentage of the sell amount
        protocolFee = outputValue.mulWadUp(_PROTOCOL_FEE_PERCENT);
        userFee = outputValue.mulWadUp(_USER_FEE_PERCENT);

        // Remove the protocol and user fees from the output amount
        outputValue -= (protocolFee + userFee);
    }
}
