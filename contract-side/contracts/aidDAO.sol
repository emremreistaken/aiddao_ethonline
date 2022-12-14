// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Base64 } from "./libraries/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "erc721a/contracts/ERC721A.sol";
import "./OptimisticOracleInterface.sol";

// EPNS PUSH Comm Contract Interface
interface IPUSHCommInterface {
    function sendNotification(address _channel, address _recipient, bytes calldata _identity) external;
}

contract aidDAO is ERC721A {
    using Strings for uint256;

    mapping(address => uint) public addressParticipated; // keeps track of total participation amount of addresses
    mapping(address => uint) public addressFunded; // keeps track of total aided $MATIC amounts of addresses
    mapping(uint256 => Aid) public aidProposals;

    struct Aid {
        uint deadline;
        bool executed; // keeps track of whether the aid is sent or not
        mapping(address => uint) aiders;

        string description;
        string proof; // to ask UMA's OO about legidity of description source
        address to; // destination to fund
        bytes OOquestion; // to get the answer from UMA'ss OOV2
        uint requestTime; // to get the answer from UMA'ss OOV2

        bool isNeedReal; // if yes, it's ready to be funded
        uint totalFunded;
    }

    uint256 public aidCounter;

    constructor() ERC721A ("aidDAO Membership", "AID") {}
    receive() external payable {}
    fallback() external payable {}

    function joinDAO() external payable {
        require(balanceOf(msg.sender) == 0, "you are already a member");
        _safeMint(msg.sender, 1);
    }

    function createAid(
        address _to,
        string memory _description,
        string memory _proof,
        uint _hoursToFund
    ) external payable DAOMemberOnly {
        Aid storage aid = aidProposals[aidCounter];

        aid.description = _description;
        aid.proof = _proof;
        aid.OOquestion = bytes(abi.encodePacked("Is the following news source 'legit and an urgent emergency' at the same time?: ", _proof, " A: 1 for YES, 0 for NO"));
        aid.to = _to;
        aid.deadline = block.timestamp + _hoursToFund * 60; // should be " * 3600" at the end, but lowered for testing purposes

        requestData(aid.OOquestion);
        aidCounter++;
    }

    modifier DAOMemberOnly() {
        require(balanceOf(msg.sender) == 1, "not a dao member");
        _;
    }

    modifier acceptedAidOnly(uint _aidIndex) {
        require(aidProposals[_aidIndex].isNeedReal == true, "aid is not proven");
        require (
            aidProposals[_aidIndex].deadline > block.timestamp,
            "deadline exceeded"
        );
        _;
    }
    
    function joinToAid(uint _aidIndex)
        external
        payable
        DAOMemberOnly
        acceptedAidOnly(_aidIndex)
    {
        Aid storage aid = aidProposals[_aidIndex];
        require(msg.value > 0, "you should make a bit aid");

        // increases participations
        if(aid.aiders[msg.sender] == 0) {
            addressParticipated[msg.sender]++;
        }
        
        addressFunded[msg.sender] += msg.value;
        aid.aiders[msg.sender] = msg.value;
        aid.totalFunded += msg.value;
    }

    modifier executableAidOnly(uint256 _aidIndex) {
        require(
            aidProposals[_aidIndex].deadline <= block.timestamp,
            "deadline is not exceeded"
        );
        require(
            aidProposals[_aidIndex].executed == false,
            "aid has been made already"
        );
        _;
    }

    function sendAid(uint256 _aidIndex)
        external
        DAOMemberOnly
        executableAidOnly(_aidIndex)
    {
        Aid storage aid = aidProposals[_aidIndex];
        (bool success, ) = address(payable(aid.to)).call{value : aid.totalFunded}("");
        require(success,"transfer failed");
        
        aid.executed = true;
    }

    /******************** DYNAMIC SOULBOUND NFT ********************/

    string svg1 = "<svg xmlns='http://www.w3.org/2000/svg' version='1.1' xmlns:xlink='http://www.w3.org/1999/xlink' xmlns:svgjs='http://svgjs.dev/svgjs' viewBox='0 0 700 700' width='700' height='700'><defs><linearGradient gradientTransform='rotate(150, 0.5, 0.5)' x1='50%' y1='0%' x2='50%' y2='100%' id='ffflux-gradient'><style>.t{ font: bold 30px sans-serif; fill: black; }.b{ font: bold 50px sans-serif; fill: black; }.f{ font: bold 50px monospace; fill: black; }.a{ font: bold 25px sans-serif; fill: black; }</style><stop stop-color='hsl(315, 100%, 72%)' stop-opacity='1' offset='0%'></stop><stop stop-color='hsl(227, 100%, 50%)' stop-opacity='1' offset='100%'></stop></linearGradient><filter id='ffflux-filter' x='-20%' y='-20%' width='140%' height='140%' filterUnits='objectBoundingBox' primitiveUnits='userSpaceOnUse' color-interpolation-filters='sRGB'><feTurbulence type='fractalNoise' baseFrequency='0.005 0.003' numOctaves='2' seed='2' stitchTiles='stitch' x='0%' y='0%' width='100%' height='100%' result='turbulence'></feTurbulence><feGaussianBlur stdDeviation='20 0' x='0%' y='0%' width='100%' height='100%' in='turbulence' edgeMode='duplicate' result='blur'></feGaussianBlur><feBlend mode='color-dodge' x='0%' y='0%' width='100%' height='100%' in='SourceGraphic' in2='blur' result='blend'></feBlend></filter></defs><rect width='700' height='700' fill='url(#ffflux-gradient)' filter='url(#ffflux-filter)'></rect><text x='50%' y='25%' class='t' dominant-baseline='middle' text-anchor='middle'>Participated aid amount:</text><text x='50%' y='35%' class='b' dominant-baseline='middle' text-anchor='middle'>";
    string svg2 = "</text><text x='50%' y='60%' class='t' dominant-baseline='middle' text-anchor='middle'>Raised aid amount in $MATIC wei:</text><text x='50%' y='70%' class='a' dominant-baseline='middle'>";
    string svg3 = "</text><text x='456' y='95%' class='f' dominant-baseline='middle'>aidDAO&#127384;</text></svg>";

    function tokenURI(uint tokenId) public view virtual override returns(string memory) {
        uint participated = addressParticipated[ownerOf(tokenId)];
        uint raised = addressFunded[ownerOf(tokenId)];

        string memory finalSvg = string(abi.encodePacked(svg1, _toString(participated), svg2, raised.toString() , svg3));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "aidDao Member #',
                        _toString(tokenId),
                        '", "description": "aidDAO aims to raise funds to people in emergency/urgent need. This NFT represents proof of membership.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(finalSvg)),
                        '"}'
                    )
                )
            )
        );

        string memory finalTokenUri = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return finalTokenUri;
    }

    error Soulbound();

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        if(from != address(0)) revert Soulbound(); // Transfers are not allowed except minting
    }

    /************ aidDAO UMA's OO implementation to check proposal legidity (Polygon Mumbai) ************/

    OptimisticOracleInterface oo = OptimisticOracleInterface(0xAB75727d4e89A7f7F04f57C00234a35950527115);

    bytes32 identifier = bytes32("YES_OR_NO_QUERY");

    function requestData(bytes memory _ancillaryData) internal {
        uint requestTime = block.timestamp; // Set the request time to the current block time.
        IERC20 bondCurrency = IERC20(0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa); // Use Mumbai WETH as the bond currency.
        uint256 reward = 0; // Set the reward to 0 (so we dont have to fund it from this contract).

        // Now, make the price request to the Optimistic oracle and set the liveness to 30 so it will settle quickly.
        /*
        We would use the lines of code below to send request, if UMA's Optimistic Oracle V2 was deployed on Polygon Mumbai.

            oo.requestPrice(identifier, requestTime, _ancillaryData, bondCurrency, reward);
            oo.setCustomLiveness(identifier, requestTime, _ancillaryData, 30);

        */
    }

    function settleRequest(uint _aidIndex) public DAOMemberOnly {
        Aid storage aid = aidProposals[_aidIndex];
        /*
        We would use the line of code below to settle wanted request, if UMA's Optimistic Oracle V2 was deployed on Polygon Mumbai.

            oo.settle(address(this), identifier, aid.requestTime, aid.OOquestion);
        
        :(
        */
    }

    function getSettledData(uint _aidIndex) public DAOMemberOnly returns (int256) {
        Aid storage aid = aidProposals[_aidIndex];
        int256 result = 1;
            /* 
            We supposed to get the settled result from the OOV2 as below:

               int256 result = oo.getRequest(address(this), identifier, aid.requestTime, aid.OOquestion).resolvedPrice;

            But unfortunately, UMA's Optimistic Oracle V2 is not currently deployed on Polygon Mumbai.
            So we pretend as we got the result equal to 1.
            Pls deploy on Polygon Mumbai. <3
            */
        
        if(result == 1 && aid.isNeedReal == false){
            aid.isNeedReal = true;
            notifyDAO(_aidIndex, aid.description);
        }

        return result;
    }

    /*************** aidDAO EPNS Push Notifications Implementation ***************/

    address EPNS_COMM_ADDRESS = 0xb3971BCef2D791bc4027BbfedFb47319A4AAaaAa;

    function notifyDAO(uint _aidIndex, string memory _description) internal {
        IPUSHCommInterface(EPNS_COMM_ADDRESS).sendNotification(
            0x48008aA5B9CA70EeFe7d1348bB2b7C3094426AA6, // from channel
            address(this), // to recipient, put address(this) in case you want Broadcast or Subset. For Targetted put the address to which you want to send
            bytes(
                string(
                    // We are passing identity here: https://docs.epns.io/developers/developer-guides/sending-notifications/advanced/notification-payload-types/identity/payload-identity-implementations
                    abi.encodePacked(
                        "0", // this is notification identity: https://docs.epns.io/developers/developer-guides/sending-notifications/advanced/notification-payload-types/identity/payload-identity-implementations
                        "+", // segregator
                        "1", // this is payload type: https://docs.epns.io/developers/developer-guides/sending-notifications/advanced/notification-payload-types/payload (1, 3 or 4) = (Broadcast, targetted or subset)
                        "+", // segregator
                        "aidDAO New Aid Alert! - Aid #",
                        _toString(_aidIndex),
                        "+", // segregator
                        _description,
                        ". Please don't leave it without support, and make your humble donation to 'Aid #",
                        _toString(_aidIndex),
                        "'. <3"
                    )
                )
            )
        );
    }
    
    function getActiveAidCount() external view returns(uint) {
        uint count;
        for(uint i; i < aidCounter; i++){
            Aid storage aid = aidProposals[i];
            if(aid.isNeedReal == true && aid.executed == false) {
                count++;
            }
        }
        
        return count;
    }
}