// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IMedia.sol";
import "./interfaces/IMarket.sol";
import "./interfaces/IReserveAuction.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTFactory is ReentrancyGuard {
    struct AuctionData {
        uint256 tokenId;
        uint256 duration;
        uint256 reservePrice;
    }

    // ============ Modifiers ============

    /**
     * @dev Modifier to check whether the `msg.sender` is the operator.
     * If it is, it will run the function. Otherwise, it will revert.
     */
    modifier onlyOperator() {
        require(msg.sender == operator);
        _;
    }

    // ============ Constructor ============

    constructor(address payable operator_) {
        // Null checks.
        require(operator_ != address(0), "Operator can't be null");

        // Initialize immutable storage.
        operator = operator_;
    }

    function mintNFTAndCreateAuction(
        IMedia.MediaData calldata mediaData,
        IMarket.BidShares calldata bidShares,
        AuctionData calldata auctionData,
        address creator,
        EIP712Signature memory creatorSignature
    ) {
        mintNFTWithSig(mediaData, bidShares, creatorSignature);

        createAuction(
            auctionData.tokenId,
            auctionData.duration,
            auctionData.reservePrice,
            creator
        );
    }

    // Allows the operator to mint an NFT.
    function mintNFTWithSig(
        IMedia.MediaData calldata mediaData,
        IMarket.BidShares calldata bidShares,
        address creator,
        EIP712Signature memory creatorSignature
    ) internal onlyOperator nonReentrant {
        IMedia(mediaAddress).mintWithSig(
            creator,
            mediaData,
            bidShares,
            creatorSignature
        );
    }

    function createAuction(
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice
    ) internal {
        IReserveAuction(mediaAddress).createAuction(
            tokenId,
            duration,
            reservePrice,
            creator,
            operator
        );
    }
}
