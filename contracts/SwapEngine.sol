
 // SPDX-License-Identifier: MIT

/**
 * PowerBull (https://powerbull.net)
 * @author  PowerBull <hello@powerbull.net>
 * @author  Zak - @zakpie (telegram)
 */

pragma solidity ^0.8.4;
pragma abicoder v2;

//import "./StructsDef.sol";
//import "hardhat/console.sol";
//import "./ContractBase.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libs/@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./libs/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/ICada.sol";
import "./Commons.sol";
//import "./libs/_IERC20.sol";
import "hardhat/console.sol";

contract SwapEngine is Context, Ownable, Commons {

    using SafeMath for uint256;

    event Receive(address _sender, uint256 _amount);


    // if add initial tx has been called already
    bool public _isAddInitialLiuqidityExecuted;

    ICada public tokenContract;
    IUniswapV2Router02 public uniswapRouter;
    address  public uniswapPair;

    IUniswapV2Pair public uniswapPairContract;

    bytes32 public TX_TRANSFER = "TX_TRANSFER"; 
    bytes32 public TX_SELL = keccak256(abi.encodePacked("TX_SELL")); 
    bytes32 public TX_BUY = keccak256(abi.encodePacked("TX_BUY"));
    bytes32 public TX_ADD_LIQUIDITY = keccak256(abi.encodePacked("TX_ADD_LIQUIDITY"));
    bytes32 public TX_REMOVE_LIQUIDITY = keccak256(abi.encodePacked("TX_REMOVE_LIQUIDIY"));


    constructor(address _tokenAddress, address _uniswapRouter) {

        tokenContract = ICada(_tokenAddress);

        _setUniswapRouter(_uniswapRouter);

    } //end constructor

    receive () external payable { emit Receive(_msgSender(), msg.value ); }

    fallback () external payable {}

    // only Token modifier
    modifier onlyTokenContract {
        require(_msgSender() == address(tokenContract), "PBULL_SWAP_ENGINE: Only Token Contract Permitted");
        _;
    }//end 


    /**
     * @dev isSellTx wether the transaction is a sell tx
     * @param msgSender__ the transaction sender
     * @param _txSender the transaction sender
     * @param _txRecipient the transaction recipient
     * @param _amount the transaction amount
     */
    function getTxType(
        address  msgSender__,
        address  _txSender, 
        address  _txRecipient, 
        uint256  _amount
    ) public view onlyTokenContract returns(bytes32) {
        

       // add liquidity 
       /*if(msgSender__ == address(uniswapRouter) && // msg.sender is same as uniswap router address
           tokenContract.allowance(_txSender, address(uniswapRouter)) >= _amount && // and user has allowed 
          _txRecipient == uniswapPair // to or recipient is the uniswap pair    
        ) {
            return TX_ADD_LIQUIDITY;
        }

        // lets check remove liquidity 
        else*/
        if (msgSender__ == address(uniswapRouter) && // msg.sender is same as uniswap router address
            _txSender  ==  address(uniswapRouter) && // _from is same as uniswap router address
            uniswapPairContract.allowance(_txRecipient, address(uniswapRouter)) >= _amount
        ) {
            return TX_REMOVE_LIQUIDITY;
        } 

         // lets detect sell
        else if (msgSender__ == address(uniswapRouter) && // msg.sender is same as uniswap router address
            tokenContract.allowance(_txSender, address(uniswapRouter)) >= _amount && // and user has allowed 
            _txRecipient == uniswapPair
        ) {
            return TX_SELL;
        }
        
        // lets detect buy 
        else if (msgSender__ == uniswapPair && // msg.sender is same as uniswap pair address
            _txSender == uniswapPair  // transfer sender or _from is uniswap pair
        ) {
            return TX_BUY;
        }

        else {
            return TX_TRANSFER;
        }
    } //end get tx type

    /**
     * @dev set uniswap router
     * @param _uniswapRouter uniswap router contract address 
     */
    function setUniswapRouter(address _uniswapRouter)  public onlyTokenContract {
        _setUniswapRouter(_uniswapRouter);
    }

    /**
     * @dev set uniswap router
     * @param _uniswapRouter uniswap router contract address 
     */
    function _setUniswapRouter(address _uniswapRouter)  private {

        require(_uniswapRouter != address(0), "PBULL#SWAP_ENGINE: ZERO_ADDRESS");

        if(_uniswapRouter == address(uniswapRouter)){
            return;
        }
          
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);

        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

        uniswapPair = uniswapFactory.getPair( address(tokenContract), uniswapRouter.WETH() );
        
        if(uniswapPair == address(0)) {
            // Create a uniswap pair for this new token
            uniswapPair = uniswapFactory.createPair( address(tokenContract), uniswapRouter.WETH() );
        }

        uniswapPairContract = IUniswapV2Pair(uniswapPair);
    } //end fun 

    /**
     * @dev get uniswap router address
     */
    function getUniswapRouter() public view returns(address) {
        return address(uniswapRouter);
    }

    /**
     * get the swap pair address
     */
    function getUniswapPair() public view returns(address) {
        return uniswapPair;
    }


    /**
    * @dev lets swap token for chain's native asset, this is bnb for bsc, eth for ethereum and ada for cardanno
    * @param _amountToken the token amount to swap to native asset
    */
    function swapTokenForETH(uint256 _amountToken) public onlyTokenContract returns(uint256) {

        require(address(uniswapRouter) != address(0), "PBULL_SWAP_ENGINE: UNISWAP_ROUTER_NOT_SET");

        address[] memory path = new address[](2);

        path[0] = address(tokenContract);
        path[1] = uniswapRouter.WETH();

        tokenContract.approve(address(uniswapRouter), _amountToken);

        uint256  currentEthBalance = address(this).balance;

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amountToken,
            0, // accept any amoun
            path,
            address(this),
            block.timestamp.add(360)
        );        

        return uint256(address(this).balance.sub(currentEthBalance));
    } //end

    
    /**
    * @dev swap ETH for tokens 
    * @param _amountETH amount to sell in ETH or native asset
    * @param _to the recipient of the tokens
    */
    function swapETHForToken(uint256 _amountETH, address _to) public payable onlyTokenContract returns(uint256)  {

        require(address(uniswapRouter) != address(0), "PBULL_SWAP_ENGINE: UNISWAP_ROUTER_NOT_SET");

        require(payable(address(this)).send(msg.value), "PBULL_SWAP_ENGINE#swapETHForToken: Failed to move ETH to contract");

        address[] memory path = new address[](2);
        
        address _tokenRecipient = _to;

        // if to is a burn or 0 address, lets get to this contract first and burn it
        if(_to == address(0)){
            _tokenRecipient = address(this);
        }

        // lets get the current token balance of the _tokenRecipient 
        uint256 _recipientTokenBalance = tokenContract.balanceOf(_tokenRecipient);

        path[0] =  uniswapRouter.WETH();
        path[1] = address(this); 

        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens {value: _amountETH} (
            0, // accept any amount
            path,
            _tokenRecipient,
            block.timestamp.add(360)
        );        

        // total tokens bought
        uint256 totalTokensBought = tokenContract.balanceOf(_tokenRecipient).sub(_recipientTokenBalance);

        if(_to == address(0)){
            tokenContract.burn(totalTokensBought);
        } 

        return totalTokensBought;
    } //end

    
    /**
     * @dev add liquidity to the swap
     * @param _amountToken token amount to add
     * @param _amountETH  native asset example: bnb to add to token as pair for liquidity
     */
    function addLquidity(uint256 _amountToken, uint256 _amountETH) public payable onlyTokenContract {

        require(address(uniswapRouter) != address(0), "PBULL_SWAP_ENGINE: UNISWAP_ROUTER_NOT_SET");

        require(payable(address(this)).send(msg.value), "PBULL_SWAP_ENGINE#addLquidity: Failed to move ETH to contract");

        tokenContract.approve(address(uniswapRouter), _amountToken);

        // add the liquidity
        uniswapRouter.addLiquidityETH { value: _amountETH } (
            address(tokenContract), //token contract address
            _amountToken, // token amount to add liquidity
            0, //amountTokenMin 
            0, //amountETHMin
            tokenContract.autoLiquidityOwner(), //owner of the liquidity
            block.timestamp.add(360) //deadline
        );

    } //end add liquidity


    /**
     * @dev add Initial Liquidity to swap exchange
     * @param _amountToken the token amount 
     */
    function addInitialLiquidity(uint256 _amountToken ) external payable onlyOwner  {

        require(address(uniswapRouter) != address(0), "PBULL_SWAP_ENGINE#addInitialLiquidity: UNISWAP_ROUTER_NOT_SET");

        require(!_isAddInitialLiuqidityExecuted,"PBULL_SWAP_ENGINE#addInitialLiquidity: function already called");
        require(msg.value > 0, "PBULL_SWAP_ENGINE#addInitialLiquidity: msg.value must exceed 0");
        require(_amountToken > 0, "PBULL_SWAP_ENGINE#addInitialLiquidity: _amountToken must exceed  0");

        require(payable(address(this)).send(msg.value), "PBULL_SWAP_ENGINE#addInitialLiquidity: Failed to move ETH to contract");

         _isAddInitialLiuqidityExecuted = true;

        tokenContract.transferFrom(_msgSender(), address(this), _amountToken);

        tokenContract.approve(address(uniswapRouter), _amountToken );

        //console.log("SWAPENGINE BALANCE ====>>> ", tokenContract.balanceOf(address(this)));

        // add the liquidity
        uniswapRouter.addLiquidityETH { value: msg.value } (
            address(tokenContract), //token contract address
            _amountToken, // token amount we wish to provide liquidity for
            _amountToken, //amountTokenMin 
            msg.value, //amountETHMin
            _msgSender(), 
            block.timestamp.add(360) //deadline
        );

    } //end add liquidity


}