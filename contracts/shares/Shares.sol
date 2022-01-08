// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interface/IERC20.sol";
import "./interface/ILandShareInitialize.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";



contract Shares is ERC20VotesUpgradeable , ILandShareInitialize{
    address _NFTAddr;
    address _NFTOwner;
    uint256 _NFTId;

    uint256 _sharesCap; 
    uint256 _sharesPublish; 
    uint256 _perSharePrice;



    function __LandShares_init(string memory name, string memory symbol , address NFTAddr , address NFTOwner , uint256 NFTId, uint256 sharesCap , uint256 sharesPublish , uint256 perSharePrice) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained(name, symbol);

        _NFTAddr = NFTAddr;
        _NFTOwner = NFTOwner;
        _NFTId = NFTId;

        _sharesCap = sharesCap;
        _sharesPublish = sharesPublish;
        _perSharePrice = perSharePrice;

        _mint(NFTOwner,_sharesCap - _sharesPublish);
    }

    function Initialize(string memory name, string memory symbol , address NFTAddr , address NFTOwner , uint256 NFTId, uint256 sharesCap , uint256 sharesPublish , uint256 perSharePrice) public initializer virtual override {
        __LandShares_init(name,symbol,NFTAddr,NFTOwner,NFTId,sharesCap,sharesPublish,perSharePrice);
    }

    function sharesCap() public virtual view returns(uint256){
        return _sharesCap;
    }

    function mint(address account, uint256 amount) public payable virtual {
        _mint(account,amount);
        (bool success,) = _NFTOwner.call{value: msg.value}("");
        require(success," transfer msg.value to NFTOwner fail");
    }

    function createProposal() public {

    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from,to,amount);
        if (from == address(0)){
            require( totalSupply() + amount < _sharesCap , " out of shresCap ");

            // 第一次mint 不需要支付购买股票的费用
            uint ts = totalSupply();
            if ( ts > 0 ){
                require(msg.value >= amount * _perSharePrice," not enough msg.value");
            }
        }
    }   

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {}

    

}