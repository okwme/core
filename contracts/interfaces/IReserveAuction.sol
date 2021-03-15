// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

/**
 * @title Interface for the Reserve Auction contract
 */
interface IReserveAuction {
    function createAuction(
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice,
        address payable creator
    ) external;
}
