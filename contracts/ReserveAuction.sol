// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMarket.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract IMediaModified {
    mapping(uint256 => address) public tokenCreators;
}

contract ReserveAuction is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    bool public paused;

    uint256 constant timeBuffer = 15 * 60; // extend 15 minutes after every bid made in last 15 minutes
    uint256 constant minBid = 1 * 10**17; // 0.1 eth

    bytes4 constant interfaceId = 0x80ac58cd; // 721 interface id
    address public zora = 0xabEFBc9fD2F806065b4f3C237d4b59D9A97Bcac7;

    mapping(uint256 => Auction) public auctions;
    uint256[] public tokenIds;

    struct Auction {
        bool exists;
        uint256 amount;
        uint256 tokenId;
        uint256 duration;
        uint256 firstBidTime;
        uint256 reservePrice;
        address payable creator;
        address payable bidder;
    }

    modifier notPaused() {
        require(!paused, "Must not be paused");
        _;
    }

    event AuctionCreated(
        uint256 tokenId,
        address zoraAddress,
        uint256 duration,
        uint256 reservePrice,
        address creator
    );
    event AuctionBid(
        uint256 tokenId,
        address zoraAddress,
        address sender,
        uint256 value,
        uint256 timestamp,
        bool firstBid,
        bool extended
    );
    event AuctionEnded(
        uint256 tokenId,
        address zoraAddress,
        address creator,
        address winner,
        uint256 amount
    );
    event AuctionCanceled(
        uint256 tokenId,
        address zoraAddress,
        address creator
    );

    constructor(address _zora) public {
        require(
            IERC165(_zora).supportsInterface(interfaceId),
            "Doesn't support NFT interface"
        );
        zora = _zora;
    }

    function updateZora(address _zora) public onlyOwner {
        require(
            IERC165(_zora).supportsInterface(interfaceId),
            "Doesn't support NFT interface"
        );
        zora = _zora;
    }

    function createAuction(
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice,
        address payable creator
    ) external notPaused {
        require(!auctions[tokenId].exists, "Auction already exists");

        tokenIds.push(tokenId);

        auctions[tokenId].exists = true;
        auctions[tokenId].duration = duration;
        auctions[tokenId].reservePrice = reservePrice;
        auctions[tokenId].creator = creator;

        IERC721(zora).transferFrom(creator, address(this), tokenId);

        emit AuctionCreated(tokenId, zora, duration, reservePrice, creator);
    }

    function createBid(uint256 tokenId) external payable notPaused {
        require(auctions[tokenId].exists, "Auction doesn't exist");
        require(
            msg.value >= auctions[tokenId].reservePrice,
            "Must send reservePrice or more"
        );
        require(
            block.timestamp <
                auctions[tokenId].firstBidTime + auctions[tokenId].duration,
            "Auction expired"
        );

        uint256 lastValue = auctions[tokenId].amount;

        bool firstBid;
        address payable lastBidder;

        // allows for auctions with starting price of 0
        if (lastValue != 0) {
            require(
                msg.value.sub(lastValue) >= minBid,
                "Must send more than last bid by minBid Amount"
            );
            lastBidder = auctions[tokenId].bidder;
        } else {
            firstBid = true;
            auctions[tokenId].firstBidTime = block.timestamp;
        }

        require(
            IMarket(zora).isValidBid(tokenId, msg.value),
            "Market: Ask invalid for share splitting"
        );

        auctions[tokenId].amount = msg.value;
        auctions[tokenId].bidder = msg.sender;

        bool extended;
        if (
            (block.timestamp -
                (auctions[tokenId].firstBidTime + auctions[tokenId].duration)) <
            timeBuffer
        ) {
            auctions[tokenId].firstBidTime += timeBuffer;
            extended = true;
        }

        if (!firstBid) {
            lastBidder.transfer(lastValue);
        }

        emit AuctionBid(
            tokenId,
            zora,
            msg.sender,
            msg.value,
            block.timestamp,
            firstBid,
            extended
        );
    }

    function endAuction(uint256 tokenId) external notPaused {
        require(auctions[tokenId].exists, "Auction doesn't exist");
        require(
            uint256(auctions[tokenId].firstBidTime) != 0,
            "Auction hasn't begun"
        );
        require(
            block.timestamp >=
                auctions[tokenId].firstBidTime + auctions[tokenId].duration,
            "Auction hasn't completed"
        );

        address winner = auctions[tokenId].bidder;
        uint256 amount = auctions[tokenId].amount;
        address payable creator = auctions[tokenId].creator;

        emit AuctionEnded(tokenId, zora, creator, winner, amount);
        delete auctions[tokenId];

        IERC721(zora).transferFrom(address(this), winner, tokenId);

        // compiler error here:
        IMarket.BidShares memory bidShares =
            IMarket(zora).bidSharesForToken(tokenId);

        // solc 6.0 method for casting payable addresses:
        address payable originalCreator =
            payable(address(IMediaModified(zora).tokenCreators(tokenId)));

        uint256 creatorAmount =
            IMarket(zora).splitShare(bidShares.creator, amount);
        uint256 sellerAmount = amount.sub(creatorAmount);

        originalCreator.transfer(creatorAmount);
        creator.transfer(sellerAmount);
    }

    function cancelAuction(uint256 tokenId) external {
        require(auctions[tokenId].exists, "Auction doesn't exist");
        require(
            auctions[tokenId].creator == msg.sender || msg.sender == owner(),
            "Can only be called by auction creator"
        );
        require(
            uint256(auctions[tokenId].firstBidTime) == 0,
            "Can't cancel an auction once it's begun"
        );
        address creator = auctions[tokenId].creator;
        IERC721(zora).transferFrom(address(this), creator, tokenId);
        emit AuctionCanceled(tokenId, zora, creator);
        delete auctions[tokenId];
    }

    function updatePaused(bool _paused) public onlyOwner {
        paused = _paused;
    }
}
