// SPDX-License-Identifier: MIT

/**
 * PowerBull (https://powerbull.net)
 * @author PowerBull <hello@powerbull.net>
 */
 
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./libs/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IHoldlersRewardComputer.sol";
import "./StructsDef.sol";
import "./Commons.sol";
import "./interfaces/ISwapEngine.sol";
import "hardhat/console.sol";
import "./interfaces/ITeams.sol";

contract Cada is   Context, Ownable, ERC20, Commons {

    event Receive(address _sender, uint256 _amount);
    event SetUniSwapRouter(address indexed _routerAddress);
    event SetAutoBurnFee(uint256 _value);
    event SetHoldlersRewardFee(uint256 _value);
    event SetLiquidityProvidersIncentiveFee(uint256 _value);
    event SetAutoLiquidityFee(uint256 _value);
    event SetAutoLiquidityOwner(address indexed _account);
    event AddMinter(address indexed _account);
    event RemoveMinter(address indexed _account);
    event SetTokenBurnStrategyContract(address indexed _contractAddress);
    event EnableBurn(bool _option);
    event EnableAutoLiquidity(bool _option);
    event EnableHoldlersReward(bool _option);
    event EnableLiquidityProvidersIncentive(bool _option);
    event SetHoldlersRewardComputer(address indexed _contractAddress);
    event SetMaxTxAmountLimitPercent(uint256  _value);
    event EnableMaxTxAmountLimit(bool _option);
    //event EnableMaxBalanceLimit(bool _option);
    event SetLiquidityProvidersIncentiveWallet(address indexed _account);
    event SetMinAmountBeforeAutoLiquidity(uint256 _amount);
    event ReleaseAccountReward(address indexed _account, uint256 _amount);
    event ExcludeFromFees(address indexed _account, bool _option);
    event SetSwapEngine(address indexed _contractAddress);
    event ExcludeFromRewards(address indexed _account, bool _option);
    event ExcludeFromMaxTxAmountLimit(address indexed _account, bool _option);
    event EnableBuyBack(bool _option);
    event SetbuyBackFee(uint256 _value);
    event SetMinAmountBeforeAutoBurn(uint256 _amount);
    event SetPercentageShareOfHoldlersRewardsForReservedPool(uint256 _valueBps);
    event SetMinPercentageOfholdlersRewardReservedPoolToMainPool(uint256 _valueBps);
    event ThrottleAccount(address indexed _account, uint256 _amountPerTx, uint256 _txIntervals);
    event UnThrottleAccountTx(address indexed _account);
    event EnableSellTax(bool _option);
    event SetSellTaxFee(uint256 _valueBps);
    event EnableTeams(bool _option);
    event SetTeamsContract(address _contractAddress);
    event SetMarketingAndCharityFee(uint256 _valueBps);
    event SetMarketingAndCharityWallet(address _account);
    event EnableMarketingAndCharity(bool _option);

    using SafeMath for uint256;

    string  private constant  _tokenName                          =    "CadaaTest v40";
    string  private constant  _tokenSymbol                        =    "CTestV40";
    uint8   private constant  _tokenDecimals                      =     9;
    uint256 private constant  _tokenSupply                        =     1_100_000_000_000_000  * (10 ** _tokenDecimals); // 1 quadrillion

    /////////////////////// This will deposit _initialPercentageOfTokensForRewardPool into the reward pool for the users to split over time /////////////
    /////////////////////// Note this is a one time during contract initialization ///////////////////////////////////////////////////////
    uint256 public constant  _initialPercentOfTokensForHoldlersRewardPool =  100; /// 1% of total supply


    bool public isAutoBurnEnabled                                  =  false;
    bool public isAutoLiquidityEnabled                             =  true;
    bool public isHoldlersRewardEnabled                            =  true; 
    bool public isLiquidityProvidersIncentiveEnabled               =  false;
    bool public isBuyBackEnabled                                   =  true;
    bool public isSellTaxEnabled                                   =  true; 
    bool public isMarketingAndCharityEnabled                       =  true;

    //limits 
    bool public isMaxTxAmountLimitEnabled                           = true;

    bool public isTeamsEnabled                                      = true;


    //using basis point, multiple number by 100  
    uint256  public  holdlersRewardFee                               =  300;     //  1% for holdlers reward pool
    uint256  public  liquidityProvidersIncentiveFee                  =  0;    //  1% for liquidity providers incentives
    uint256  public  autoLiquidityFee                                =  300;    // 1% fee charged on tx for adding liquidity pool
    uint256  public  autoBurnFee                                     =  0;   //   1% will be burned
    uint256  public  buyBackFee                                      =  200; //   1% will be used for buyback
    uint256  public  sellTaxFee                                      =  200;  // a sell tax fee, which applies to sell only
    uint256  public  marketingAndCharityFee                          =  200;

    //buyback 
    uint256 public minAmountBeforeSellingTokenForBuyBack             =  200_000_000 * (10 ** _tokenDecimals); 
    uint256 public minAmountBeforeSellingBNBForBuyBack               =  1 ether;
    uint256 public buyBackETHFundsSplitDivisor                       =  100;
    uint256 public numOfBuyBackPerAllocatedFunds                     =  10;  
    
    uint256 public allocatedFundsForBuyBack;
    uint256 public buyBackTokenPool;
    uint256 public buyBackETHPool;
    uint256 public remainingNumOfBuyBackForAllocatedFunds;
    
    uint256 public buyBackTotalTokensBought;
    uint256 public buyBackTotalTokensBoughtETH;

    // funds pool
    uint256  public autoLiquidityPool;
    uint256  public autoBurnPool;
    uint256  public liquidityProvidersIncentivePool;

    //////////////////////////////// START REWARD POOL ///////////////////////////
    uint256  public holdlersRewardMainPool;
    
    // reward pool reserve  used in replenishing the main pool any time someone withdraw else
    // the others holdlers will see a reduction  in rewards
    uint256  public holdlersRewardReservedPool;


    ////// percentage of reward we should allocate to  reserve pool
    uint256  public percentageShareOfHoldlersRewardsForReservedPool                       =  2000; /// 25% in basis point system

    // The minimum amount required to keep in the holdlersRewardsReservePool
    // this means if the reserve pool goes less than minPercentOfReserveRewardToMainRewardPool  of the main pool, use 
    // next collected fee for rewards into the reserve pool till its greater than minPercentOfReserveRewardToMainRewardPool
    uint256 public minPercentageOfholdlersRewardReservedPoolToMainPool                    =  2000; /// 20% in basis point system


    // marketing and charity wallet 
    address marketingAndCharityWallet   = 0x261854A809D7Fe99C78073df58D82604374fF983;

    ///////////////////////////////// END  REWARD POOL ////////////////////////////

    // liquidity owner
    address public autoLiquidityOwner;

    //max transfer amount  ( anti whale check ) in BPS (Basis Point System )
    uint256 public maxTxAmountLimitPercent                                  =  2000; //20% of total supply 

    //minimum amount before adding auto liquidity
    uint256 public minAmountBeforeAutoLiquidity                             =   100_000_000 * (10 ** _tokenDecimals);    

    // minimum amount before auto burn
    uint256 public minAmountBeforeAutoBurn                                  =   500_000_000 * (10 ** _tokenDecimals);    


    ///////////////////// START  MAPS ///////////////////////

    //accounts excluded from fees
    mapping(address => bool) public excludedFromFees;
    mapping(address => bool) public excludedFromRewards;
    mapping(address => bool) public excludedFromMaxTxAmountLimit;
    
    //throttle acct tx
    mapping(address => StructsDef.AccountThrottleInfo) public throttledAccounts;

    // burn history info
    //BurnInfo[] public  burnHistoryInfo;

    uint256 public totalTokenBurns;

    //permitted minters 
    mapping(address => bool)  public  minters;

    // permit nonces
    mapping(address => uint) public nonces;
    
    //acounts deposit info mapping keeping all user info
    // address => initial Deposit timestamp
    mapping(address => StructsDef.HoldlerInfo) private holdlersInfo;

    ////////////////// END MAPS ////////////////


    uint256 public totalRewardsTaken;

    bool isSwapAndLiquidifyLocked;

    // extending erc20 to support permit 
    bytes32 public DOMAIN_SEPARATOR;
    
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;


    // timestamp the contract was deployed
    uint256 public deploymentTimestamp;

 

    //aggregate of all deposits info
    //StructsDef.AccountInfo  public accountsInfoAggregate;

    // total token holders
    uint256 public totalTokenHolders;

    // external contracts 
    IHoldlersRewardComputer   public  holdlersRewardComputer;
    ISwapEngine public swapEngine;
    ITeams   public teamsContract;
    
    address  public  uniswapRouter;
    address  public  uniswapPair;

    //////// WETHER the token is initialized or not /////////////
    bool public initialized;

    // constructor 
    constructor() ERC20 (_tokenName,_tokenSymbol, _tokenDecimals) {

        // mint 
        _mint(_msgSender(), _tokenSupply);

        // lets deposit holdlers reward pool initial funds 
        processHoldlersRewardPoolInitialFunds();
    
        //excludes for 
        excludedFromFees[address(this)]               =  true;
        excludedFromRewards[address(this)]            =  true;
        excludedFromMaxTxAmountLimit[address(this)]   =  true;

        //excludes for owner
        excludedFromFees[_msgSender()]                =  true;
        excludedFromMaxTxAmountLimit[_msgSender()]    =  true;

        // set auto liquidity owner
        autoLiquidityOwner                             = _msgSender();

        // set the deploymenet time
        deploymentTimestamp                            = block.timestamp;

        // permit domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name())),
                keccak256(bytes('1')),
                getChainId(),
                address(this)
            )
        );

    } //end constructor 
    

    /**
     * initialize the project
     * @param  _uniswapRouter the uniswap router
     * @param  _holdlersRewardComputer the holdlers reward computer
     *  @param  _swapEngine the swap engine address
     */
    function _initializeContract (
        address  _uniswapRouter, 
        address  _swapEngine,
        address  _holdlersRewardComputer
    )  public onlyOwner {
        
        require(!initialized, "CADA: ALREADY_INITIALIZED");
        require(_uniswapRouter != address(0), "CADA: INVALID_UNISWAP_ROUTER");
        require(_swapEngine != address(0), "CADA: INVALID_SWAP_ENGINE_CONTRACT");
        require(_holdlersRewardComputer != address(0), "CADA: INVALID_HOLDLERS_REWARD_COMPUTER_CONTRACT");

        // set _uniswapRouter
        uniswapRouter = _uniswapRouter;

        // this will update the uniswap router again
        setSwapEngine(_swapEngine);

        // exclude swap engine from all limits
        excludedFromFees[_swapEngine]                =  true;
        excludedFromRewards[_swapEngine]             =  true;
        excludedFromMaxTxAmountLimit[_swapEngine]    =  true;

        holdlersRewardComputer = IHoldlersRewardComputer(_holdlersRewardComputer);

        initialized = true;

    }   //end intialize


    /**
     * @dev processRewardPool Initial Funds 
     */
     function processHoldlersRewardPoolInitialFunds() private {

        require(!initialized, "CADA: ALREADY_INITIALIZED");

         // if no tokens were assign to the rewards dont process
        if(_initialPercentOfTokensForHoldlersRewardPool == 0){
            return;
        }
        
        //let get the rewardPool initial funds 
        uint256 rewardPoolInitialFunds = percentToAmount(_initialPercentOfTokensForHoldlersRewardPool, totalSupply());

        //first of all lets move funds to the contract 
        internalTransfer(_msgSender(), address(this), rewardPoolInitialFunds,"REWARD_POOL_INITIAL_FUNDS_TRANSFER_ERROR", true);

        uint256 rewardsPoolsFundSplit = rewardPoolInitialFunds.sub(2);

         // lets split them 50% 50% into the rewardmainPool and rewards Reserved pool
         holdlersRewardMainPool = holdlersRewardMainPool.add(rewardsPoolsFundSplit);

         // lets put 50% into the reserve pool
         holdlersRewardReservedPool = holdlersRewardReservedPool.add(rewardsPoolsFundSplit);
    } //end function


    receive () external payable { emit Receive(_msgSender(), msg.value ); }

    fallback () external payable {}

    /**
     * lock swap or add liquidity  activity
     */
    modifier lockSwapAndLiquidify {
        isSwapAndLiquidifyLocked = true;
        _;
        isSwapAndLiquidifyLocked = false;
    }

    /**
     * get chain Id 
     */
    function getChainId() public view returns (uint256) {
        uint256 id;
        assembly { id := chainid() }
        return id;
    }

    /**
     * @dev erc20 permit 
     */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'CADA: PERMIT_EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'CADA: PERMIT_INVALID_SIGNATURE');
        _approve(owner, spender, value);
    } 


    /**
     * realBalanceOf - get account real balance
     */
    function realBalanceOf(address _account)  public view returns(uint256) {
        return super.balanceOf(_account);
    }

    /**
     * override balanceOf - This now returns user balance + reward
     */
    function balanceOf(address _account) override public view returns(uint256) {

        uint256 accountBalance = super.balanceOf(_account);

        if(accountBalance <= 0){
            accountBalance = 0;
        }
        
        uint256 reward = getReward(_account);

        if(reward <= 0){
            return accountBalance;
        }

        return (accountBalance.add(reward));
    } //end fun


    ////////////////////////// HOLDERS REWARD COMPUTER FUNCTIONS ///////////////////
    /**
     * get an account reward 
     * @param _account the account to get the reward info
     */
    function getReward(address _account) public view returns(uint256) {
        
       
        if(!isHoldlersRewardEnabled || excludedFromRewards[_account]) {
            return 0;
        }

        uint256 reward = holdlersRewardComputer.getReward(_account);

       // console.log("REWARD ===========>>>>>>>>", reward);

        if(reward <= 0){
            return 0;
        }

        return reward;
        
    }//end get reward

    /**
     * @dev the delay in seconds before a holdlers starts seeing rewards after initial deposit
     * @return time in seconds 
     */
    function rewardStartDelay() public view returns(uint256) {
       return holdlersRewardComputer.rewardStartDelay();
    } 

    /**
     * @dev set the number of delay in time before a reward starts showing up
     * @param _delayInSeconds the delay in seconds
     */
    function setRewardStartDelay(uint256 _delayInSeconds) public onlyOwner {
        holdlersRewardComputer.setRewardStartDelay(_delayInSeconds);
    } 


    /**
     * @dev the minimum expected holdl period 
     * @return time in seconds 
     */
     function minExpectedHoldlPeriod() public view returns (uint256) {
        return holdlersRewardComputer.minExpectedHoldlPeriod();
     }

    /**
     * @dev set the minimum expected holdl period 
     * @param _timeInSeconds time in seconds 
     */
     function setMinExpectedHoldlPeriod(uint256 _timeInSeconds) public onlyOwner  {
         holdlersRewardComputer.setMinExpectedHoldlPeriod(_timeInSeconds);
     }

    ////////////////////////// END HOLDERS REWARD COMPUTER FUNCTIONS ///////////////////

    /**
     * @dev get initial deposit time
     * @param _account the account to get the info
     * @return account tx info
     */
    function getHoldlerInfo(address _account) public view returns (StructsDef.HoldlerInfo memory) {
        return holdlersInfo[_account];
    }

 
    ///////////////////////// START MINT OPERATIONS ///////////////////

    modifier onlyMinter {
        require(minters[_msgSender()],"CADA: ONLY_MINTER_PERMITED");
        _;
    }

    /**
     * mint new tokens
     * @param account - the account to mint token to 
     * @param amount - total number of tokens to mint
     */
    function mint(address account, uint256 amount) public onlyMinter {

        // before mint, lets check if the account initial balance is 0, then we have a new holder
        if(_balances[account] == 0 && amount > 0) {
            totalTokenHolders = totalTokenHolders.add(1);
        }

        _mint(account, amount);
    }

    /**
     * @dev add or remove minter 
     * @param _account the account to add or remove minter
     * @param _option  true to enable as minter, false to disable as minter
     */
    function setMinter(address _account, bool _option) public onlyOwner {
        require(_account != address(0),"CADA: SET_MINTER_INVALID_ADDRESS");
        minters[_account] = _option;
        emit AddMinter(_account);
    }

    //////////////////////////////// END MINT OPERATIONS //////////////////////


    /**
     * @dev token burn operation override 
     * @param account the account to burn token from
     * @param amount the total number of tokens to burn
     */    
    function _burn(address account, uint256 amount) override internal virtual {

        super._burn(account,amount);

        //calculate the no of token holders
        if(_balances[account] == 0 && totalTokenHolders > 0){
            totalTokenHolders = totalTokenHolders.sub(1);
        }
    } //end burn override



    //////////////////////// START OPTION SETTER /////////////////

    /**
     * @dev set auto liquidity owner address
     * @param _account the EOS address for system liquidity
     */
     function setAutoLiquidityOwner(address _account) public onlyOwner {
         autoLiquidityOwner = _account;
         emit SetAutoLiquidityOwner(_account);
    }


    /**
     * @dev enable or disable auto burn 
     * @param _option true to enable, false to disable
     */
    function enableAutoBurn(bool _option) public onlyOwner {
        isAutoBurnEnabled = _option;
        emit EnableBurn(_option);
    }


    /**
     * @dev enable or disable auto buyback 
     * @param _option true to enable, false to disable
     */
    function enableBuyBack(bool _option) public onlyOwner {
        isBuyBackEnabled = _option;
        emit EnableBuyBack(_option);
    }

    /**
     * @dev enable or disable auto liquidity 
     * @param _option true to enable, false to disable
     */
    function enableAutoLiquidity(bool _option) public onlyOwner {
        isAutoLiquidityEnabled = _option;
        emit EnableAutoLiquidity(_option);
    }


    /**
     * @dev enable or disable holdlers reward
     * @param _option true to enable, false to disable
     */
    function enableHoldlersReward(bool _option) public onlyOwner {
        isHoldlersRewardEnabled = _option;
        emit EnableHoldlersReward(_option);
    }

    /**
     *  @dev enable or disable liquidity providers incentives
     *  @param _option true to enable, false to disable
     */
    function enableLiquidityProvidersIncentive(bool _option) public onlyOwner {
        isLiquidityProvidersIncentiveEnabled = _option;
        emit EnableLiquidityProvidersIncentive(_option);
    }

    /**
     *  @dev enable or disable max transaction amount limit
     *  @param _option true to enable, false to disable
     */
    function enableMaxTxAmountLimit(bool _option) public onlyOwner {
        isMaxTxAmountLimitEnabled = _option;
        emit EnableMaxTxAmountLimit(_option);
    }


    /**
     * @dev enable or disable sell Tax
     * @param _option true to enable, false to disable
     */
    function enableSellTax(bool _option) public onlyOwner {
        isSellTaxEnabled = _option;
        emit EnableSellTax(_option);
    }

    /**
     * @dev enable or disable all fees 
     * @param _option true to enable, false to disable
     */
    function enableAllFees(bool _option) public onlyOwner {
        isAutoBurnEnabled                       = _option;
        isBuyBackEnabled                        = _option;
        isAutoLiquidityEnabled                  = _option;
        isHoldlersRewardEnabled                 = _option;
        isLiquidityProvidersIncentiveEnabled    = _option;
        isSellTaxEnabled                        = _option;
    }


    // lets enable contingence
    function enableTeams(bool _option) public onlyOwner {
        isTeamsEnabled = _option;
        emit EnableTeams(_option);
    }

    // enable marketing or charift
    function enableMarketingAndCharity(bool _option) public onlyOwner {
        isMarketingAndCharityEnabled = _option;
        emit EnableMarketingAndCharity(_option);
    }
    
    
    //////////////////// END OPTION SETTER //////////



    ////////////// ACCOUNT TX THROTTLE FOR BOTS //////////////

    /**
     * @dev throttle account tx 
     * @param _account an address of the account to throttle
     * @param _txAmountLimitPercent max amount per tx in percentage in relative to totalSupply a throttled account can have
     * @param _txIntervals time interval per transaction
     */
    function throttleAccountTx(
        address _account, 
        uint256 _txAmountLimitPercent,
        uint256 _txIntervals
    ) public onlyOwner {

        require(_account != address(0),"CADA: INVALID_ACCOUNT_ADDRESS");

        // if the _amountPerTx is greater the maxTxAmount, revert
        require(_txAmountLimitPercent <= maxTxAmountLimitPercent, "CADA: _txAmountLimitPercent exceeds maxTxAmountLimitPercent");

        throttledAccounts[_account] = StructsDef.AccountThrottleInfo(_txAmountLimitPercent, _txIntervals, 0);

        emit ThrottleAccount(_account, _txAmountLimitPercent, _txIntervals);
    } //end function

    /**
     * @dev unthrottle account tx
     * @param _account the account address to unthrottle its tx
     */
    function unThrottleAccountTx(
        address _account
    ) public onlyOwner {

        require(_account != address(0),"CADA: INVALID_ACCOUNT_ADDRESS");

        delete  throttledAccounts[_account];

        emit UnThrottleAccountTx(_account);
    } //end function

    ////////////////// END THROTTLE BOTS /////////////////////

    ///////////////////// START  SETTER ///////////////
     
     /**
     * @dev set the auto burn fee
     * @param _valueBps the fee value in basis point system
     */
    function setAutoBurnFee(uint256 _valueBps) public onlyOwner { 
        autoBurnFee = _valueBps;
        emit SetAutoBurnFee(_valueBps);
    }

    /**
     * @dev set the auto buyback fee
     * @param _valueBps the fee value in basis point system
     */
    function setbuyBackFee(uint256 _valueBps) public onlyOwner { 
        buyBackFee = _valueBps;
        emit SetbuyBackFee(_valueBps);
    }

    /**
     * @dev set holdlers reward fee
     * @param _valueBps the fee value in basis point system
     */
    function setHoldlersRewardFee(uint256 _valueBps) public onlyOwner { 
        holdlersRewardFee = _valueBps;
        emit SetHoldlersRewardFee(_valueBps);
    }


    /**
     * @dev set liquidity providers incentive fee
     * @param _valueBps the fee value in basis point system
     */
    function setLiquidityProvidersIncentiveFee(uint256 _valueBps) public onlyOwner { 
        liquidityProvidersIncentiveFee = _valueBps;
        emit SetLiquidityProvidersIncentiveFee(_valueBps);
    }

    /**
     * @dev auto liquidity fee 
     * @param _valueBps the fee value in basis point system
     */
    function setAutoLiquidityFee(uint256 _valueBps) public onlyOwner { 
        autoLiquidityFee = _valueBps;
        emit SetAutoLiquidityFee(_valueBps);
    }


    /**
     * @dev set Sell Tax Fee
     * @param _valueBps the fee value in basis point system
     */
    function setSellTaxFee(uint256 _valueBps) public onlyOwner { 
        sellTaxFee = _valueBps;
        emit SetSellTaxFee(_valueBps);
    }

    /**
     * set marketing and charity fee
     */
    function setMarketingAndCharityFee(uint256 _valueBps) public onlyOwner { 
        marketingAndCharityFee = _valueBps;
        emit SetMarketingAndCharityFee(_valueBps);
    }

    /**
     * @dev setTeamsContract
     * @param _contractAddress the contract address 
     */
    function setTeamsContract(address _contractAddress)  public onlyOwner { 
        teamsContract = ITeams(_contractAddress);
        emit SetTeamsContract(_contractAddress);
    }


    //////////////////////////// END  SETTER /////////////////


    /**
     * @dev get total fee 
     * @return the total fee in uint256 number
     */
    function getTotalFee() public view returns(uint256){

        uint256 fee = 0;

        if(isAutoBurnEnabled){ fee += autoBurnFee; }
        if(isBuyBackEnabled){ fee += buyBackFee; }
        if(isAutoLiquidityEnabled){ fee += autoLiquidityFee; }
        if(isHoldlersRewardEnabled){ fee += holdlersRewardFee; }
        if(isLiquidityProvidersIncentiveEnabled){ fee += liquidityProvidersIncentiveFee; }
        if(isSellTaxEnabled) { fee += sellTaxFee; }
        if(isMarketingAndCharityEnabled) { fee += marketingAndCharityFee; }

        return fee;
    } //end function


    /**
     * set marketing and charity fee
     */
    function setMarketingAndCharityWallet(address _account) public onlyOwner {
        marketingAndCharityWallet = _account;
        emit SetMarketingAndCharityWallet(_account);
    }

    /**
     * @dev set max transfer limit in percentage
     * @param _valueBps the max transfer limit value in basis point system
     */
    function setMaxTxAmountLimitPercent(uint256 _valueBps) public onlyOwner {
        maxTxAmountLimitPercent = _valueBps;
        emit SetMaxTxAmountLimitPercent(_valueBps);
    }

    /**
     * @dev set holders reward computer contract called HoldlEffect
     * @param _contractAddress the contract address
     */
    function setHoldlersRewardComputer(address _contractAddress) public onlyOwner {
        require(_contractAddress != address(0),"CADA: SET_HOLDLERS_REWARD_COMPUTER_INVALID_ADDRESS");
        holdlersRewardComputer = IHoldlersRewardComputer(_contractAddress);
        emit SetHoldlersRewardComputer(_contractAddress);
    }


    /**
     * @dev set the token swap engine
     * @param _swapEngineContract the contract address of the swap engine
     */
    function setSwapEngine(address _swapEngineContract)  public onlyOwner {
        
        require(_swapEngineContract != address(0),"CADA: SET_SWAP_ENGINE_INVALID_ADDRESS");
        
        swapEngine = ISwapEngine(_swapEngineContract);

        excludedFromFees[_swapEngineContract]                =  true;
        excludedFromRewards[_swapEngineContract]             =  true;
        excludedFromMaxTxAmountLimit[_swapEngineContract]    =  true;

        // lets reset setUniswapRouter
        setUniswapRouter(uniswapRouter);

        emit SetSwapEngine(_swapEngineContract);
    }


     /**
     * @dev set uniswap router address
     * @param _uniswapRouter uniswap router contract address
     */
    function setUniswapRouter(address _uniswapRouter) public onlyOwner {
        
        require(_uniswapRouter != address(0), "CADA: INVALID_ADDRESS");

        uniswapRouter = _uniswapRouter;

        //set uniswap address
        swapEngine.setUniswapRouter(_uniswapRouter);
       
        uniswapPair = swapEngine.getUniswapPair();

        // lets disable rewards for uniswap pair and router
        excludedFromRewards[_uniswapRouter] = true;
        excludedFromRewards[uniswapPair] = true;

        emit SetUniSwapRouter(_uniswapRouter);
    } 


    ////////////////// START EXCLUDES ////////////////

    /**
     * @dev exclude or include  an account from paying fees
     * @param _option true to exclude, false to include
     */
    function excludeFromFees(address _account, bool _option) public onlyOwner {
        excludedFromFees[_account] = _option;
        emit ExcludeFromFees(_account, _option);
    }

    /**
     * @dev exclude or include  an account from getting rewards
     * @param _option true to exclude, false to include
     */
    function excludeFromRewards(address _account, bool _option) public onlyOwner {
        excludedFromRewards[_account] = _option;
        emit ExcludeFromRewards(_account, _option);
    }

    /**
     * @dev exclude or include  an account from max transfer limits
     * @param _option true to exclude, false to include
     */
    function excludeFromMaxTxAmountLimit(address _account, bool _option) public onlyOwner {
        excludedFromMaxTxAmountLimit[_account] = _option;
        emit ExcludeFromMaxTxAmountLimit(_account, _option);
    }


    /**
     * lets exclude an account from tx throttle
     */

    //////////////////// END EXCLUDES ///////////////////


    /**
     * @dev minimum amount before adding auto liquidity
     * @param _amount the amount of tokens before executing auto liquidity
     */
    function setMinAmountBeforeAutoLiquidity(uint256 _amount) public onlyOwner {
        minAmountBeforeAutoLiquidity = _amount;
        emit SetMinAmountBeforeAutoLiquidity(_amount);
    }

    /**
     * @dev set min amount before auto burning
     * @param _amount the minimum amount when reached we should auto burn
     */
    function setMinAmountBeforeAutoBurn(uint256 _amount) public onlyOwner {
        minAmountBeforeAutoBurn = _amount;
        emit SetMinAmountBeforeAutoBurn(_amount);
    }


    /**
     * set the min amount of reserved rewards pool to main rewards pool
     * @param _valueBps the value in basis point system
     */
    function setMinPercentageOfholdlersRewardReservedPoolToMainPool(uint256 _valueBps) public onlyOwner {
        minPercentageOfholdlersRewardReservedPoolToMainPool  = _valueBps;
        emit SetMinPercentageOfholdlersRewardReservedPoolToMainPool(_valueBps);
    }//end fun 


    /**  
     * set the the percentage share of holdlers rewards to be saved into the reserved pool
     * @param _valueBps the value in basis point system
     */
    function setPercentageShareOfHoldlersRewardsForReservedPool(uint256 _valueBps) public onlyOwner {
        percentageShareOfHoldlersRewardsForReservedPool = _valueBps;
        emit SetPercentageShareOfHoldlersRewardsForReservedPool(_valueBps);
    }//end fun 




    ////////// START SWAP AND LIQUIDITY ///////////////

    /**
    * @dev lets swap token for chain's native asset 
    * this is bnb for bsc, eth for ethereum and ada for cardanno
    * @param _amountToken the amount of tokens to swap for ETH
    */
    function swapTokenForETH(uint256 _amountToken) private returns(uint256) {

        if(realBalanceOf(address(0)) < _amountToken) {
            return 0;
        }

         //lets move the token to swap engine first
        internalTransfer(address(0), address(swapEngine), _amountToken, "SWAP_TOKEN_FOR_ETH_ERROR", false);
        
        //now swap your tokens
        return swapEngine.swapTokenForETH(_amountToken, address(this));
    }

    /**
     * @dev add liquidity
     * @param _amountToken amount of tokens to add 
     * @param _amounthETH the amount in the native asset example BNB to add
     */
    function _addLquidity(uint256 _amountToken, uint256 _amounthETH) private  {
       
        //lets move the token to swap engine first
        internalTransfer(address(0), address(swapEngine), _amountToken, "ADD_LIQUIDITY_ERROR", false);
        
        // now add the liquidity
        swapEngine.addLiquidity{value: _amounthETH}( _amountToken, _amounthETH );
    } //end add liquidity


    /**
     * @dev swap and add liquidity
     * @param _amountToken amount of tokens to swap and liquidity 
     */
    function swapAndLiquidify(uint256 _amountToken) private lockSwapAndLiquidify {

        require(_amountToken > 0, "CADA: ZERO_AMOUNT");

        // lets check if we have to that amount else abort operation
        if(balanceOf(address(this)) < _amountToken){
            return;
        }

        uint256 tokenAmountHalf = _amountToken.div(2);
        
        //lets swap to get some base asset
        uint256 swappedEthAmount = swapTokenForETH(tokenAmountHalf);

        _addLquidity(tokenAmountHalf, swappedEthAmount);

    } //end 


    /**
     * @dev buyback tokens with the native asset and burn
     * @param _amountETH the total number of native asset to be used for buying back
     * @return the number of tokens bought and burned
     */
    function executeTokenBuyBack(uint256 _amountETH) private lockSwapAndLiquidify returns(uint256) {

        // if we do not have enough eth, silently abort
        if( _amountETH == 0 || payable(address(this)).balance < _amountETH ){
            return 0;
        }

        // the first param is the amount of native asset to buy token with
        // the second param is the burn address
        return swapEngine.swapETHForToken {value: _amountETH} ( _amountETH, address(0) );
    } 
    ///////////// END SWAP AND LIQUIDITY ////////////

    mapping(address => uint256) lol;

    /**
     * override _transfer
     * @param sender the token sender
     * @param recipient the token recipient
     * @param amount the number of tokens to transfer
     */
     function _transfer(address sender, address recipient, uint256 amount) override internal virtual {

        // check if the contract has been initialized
        require(initialized, "CADA: CONTRACT_NOT_INITIALIZED");        
        require(amount > 0, "CADA: ZERO_AMOUNT");
        require(balanceOf(sender) >= amount, "CADA: INSUFFICIENT_BALANCE");
        require(sender != address(0), "CADA: INVALID_SENDER");
        require(recipient != address(0), "CADA: INVALID_RECIPIENT");


        // before we process anything, lets release senders reward
        releaseAccountReward(sender);

        // lets check if we have gain +1 user
        // before transfer if recipient has no tokens, means he or she isnt a token holder
        if(_balances[recipient] == 0) {
            totalTokenHolders = totalTokenHolders.add(1);
        } //end if


        //at this point lets get transaction type
        bytes32 txType = swapEngine.getTxType(_msgSender(), sender, recipient, amount);

        uint256 amountMinusFees = _processBeforeTransfer(sender, recipient, amount, txType);

        _balances[sender] = _balances[sender].sub(amountMinusFees, "CADA: TRANSFER_AMOUNT_EXCEEDS_BALANCE"); //, "CADA: Transfer amount exceeds balance"
        _balances[recipient] = _balances[recipient].add(amountMinusFees);
        

        // lets check i we have lost one holdler
        if(totalTokenHolders > 0) { 
            if(_balances[sender] == 0) totalTokenHolders = totalTokenHolders.sub(1); 
        } //end if 
        

        // lets update holdlers info
        updateHoldlersInfo(sender, recipient);

        // if faction is enabled, lets log the transfer tx
        if(isTeamsEnabled && address(teamsContract) != address(0)) {
            teamsContract.logTransferTx(txType, _msgSender(), sender, recipient, amount, amountMinusFees);
        }
        
        emit Transfer(sender, recipient, amountMinusFees);
    } //end 

    /**
     * tx type to string for testing only
     * @param _txType the transaction type
     */
    function txTypeToString(bytes32 _txType) public view returns (string memory) {
        if(_txType == swapEngine.TX_BUY()) { return "BUY_TRANSACTION"; }
        else if(_txType == swapEngine.TX_SELL()){ return "SELL_TRANSACTION"; }
        else if(_txType == swapEngine.TX_ADD_LIQUIDITY()){ return "ADD_LIQUIDITY_TRANSACTION"; }
        else if(_txType == swapEngine.TX_REMOVE_LIQUIDITY()){ return "ADD_REMOVE_TRANSACTION"; }
        else { return "TRANSFER_TRANSACTION"; }
    } 

    /**
     * @dev pre process transfer before the main transfer is done
     * @param sender the token sender
     * @param recipient the token recipient
     * @param amount the number of tokens to transfer
     */
     function _processBeforeTransfer(address sender, address recipient, uint256 amount,  bytes32 txType)  private returns(uint256) {

        /* 
        console.log("");
        console.log("uniswapRouter ====>> ", uniswapRouter );
        console.log("uniswapPair ====>> ", uniswapPair );
        console.log("msgSender ====>> ", _msgSender()  );
        console.log("sender ====>> ", sender );
        console.log("recipient ====>> ", recipient );
        console.log("txType ===========>>>> ", txTypeToString(txType) );
        */

         // dont tax some operations
        if(txType == swapEngine.TX_REMOVE_LIQUIDITY() || 
           sender == address(swapEngine) || 
           isSwapAndLiquidifyLocked == true
        ) {
            return amount;
        }


        // if max transfer limit is set, if the amount to process exceeds the limit per transfer
        if( isMaxTxAmountLimitEnabled || !excludedFromMaxTxAmountLimit[sender] ){

            uint256 _maxTxAmountLimit = _getMaxTxAmontLimit();
            
            // amount should be less than _maxTxAmountLimit
            require(amount < _maxTxAmountLimit, string(abi.encodePacked("CADA: AMOUNT_EXCEEDS_TRANSFER_LIMIT"," ", bytes32(_maxTxAmountLimit) )) );
        } // end if max transfer limit is set

        
        // lets check if the account's address has been thorttled
        StructsDef.AccountThrottleInfo storage throttledAccountInfo = throttledAccounts[sender];

        // if the tx is actually throttled
        if(throttledAccountInfo.timeIntervalPerTx > 0) {

            // if the lastTxTime is 0, means its the first tx no need to check
            if(throttledAccountInfo.lastTxTime > 0) {

                uint256 lastTxDuration = (block.timestamp - throttledAccountInfo.lastTxTime);    

                // lets now check the last tx time is less than the 
                if(lastTxDuration  < throttledAccountInfo.timeIntervalPerTx ) {
                    uint256 nextTxTimeInSecs = (throttledAccountInfo.timeIntervalPerTx.sub(lastTxDuration)).div(1000);
                    revert( string(abi.encodePacked("CADA:","ACCOUNT_THROTTLED_SEND_AFTER_", nextTxTimeInSecs)) );
                } //end if
            } //end if we have last tx

            //lets check the txAmountLimitPercent limit
            if(throttledAccountInfo.txAmountLimitPercent > 0){

                uint256 _throttledTxAmountLimit = percentToAmount(throttledAccountInfo.txAmountLimitPercent, totalSupply());

                if(amount > _throttledTxAmountLimit) {
                    revert( string(abi.encodePacked("CADA:","ACCOUNT_THROTTLED_AMOUNT_EXCEEDS_", _throttledTxAmountLimit)) );
                }

            } //end amount limit

            // update last tx time
            throttledAccounts[sender].lastTxTime = block.timestamp;
        } //end if tx is throttled


        // if sender is excluded from fees
        if( excludedFromFees[sender] || excludedFromFees[recipient] ){
            return amount;
        }
        
        //lets get totalTax to deduct
        uint256 totalFeeAmount =  percentToAmount(getTotalFee(), amount);

        //lets take the fee to system account
        internalTransfer(sender, address(this), totalFeeAmount, "TOTAL_FEE_AMOUNT_TRANSFER_ERROR", false);

        // take the fee amount from the amount
        uint256 amountMinusFee = amount.sub(totalFeeAmount);


        //process burn , here, the burn is not immediately carried out
        // we provide a strategy to handle the burn from time to time
        if(isAutoBurnEnabled && autoBurnFee > 0) {
            autoBurnPool = autoBurnPool.add(percentToAmount(autoBurnFee, amount) );
        } //end process burn 


        //compute amount for liquidity providers fund
        if(isLiquidityProvidersIncentiveEnabled && liquidityProvidersIncentiveFee > 0) {
            
            //lets burn this as we will auto mint lp rewards for the staking pools
            uint256 lpFeeAmount = percentToAmount( liquidityProvidersIncentiveFee, amount);

            autoBurnPool = autoBurnPool.add(lpFeeAmount);  
        } //end if

        //lets do some burn now 
        if(minAmountBeforeAutoBurn > 0 && autoBurnPool >= minAmountBeforeAutoBurn) {
            
            uint256 amountToBurn = autoBurnPool;
            
            _burn(address(this), amountToBurn);
            
            if(autoBurnPool > amountToBurn){
                autoBurnPool = autoBurnPool.sub(amountToBurn);
            } else {
                autoBurnPool = 0;
            }

            totalTokenBurns = totalTokenBurns.add(amountToBurn);
        } //end auto burn 

        /////////////////////// START BUY BACK ////////////////////////

        // check and sell tokens for bnb
        if(isBuyBackEnabled && buyBackFee > 0){
            // handle buy back 
            handleBuyBack( sender, amount, txType );
        }//end if buyback is enabled


         //////////////////////////// START AUTO LIQUIDITY ////////////////////////
        if(isAutoLiquidityEnabled && autoLiquidityFee > 0){
            
           // lets set auto liquidity funds 
           autoLiquidityPool =  autoLiquidityPool.add( percentToAmount(autoLiquidityFee, amount) );

            
            //if tx is transfer only, lets do the sell or buy
            if(txType == swapEngine.TX_TRANSFER()) {

                //take snapshot
                uint256 amounToLiquidify = autoLiquidityPool;

                if(amounToLiquidify >= minAmountBeforeAutoLiquidity){

                    //lets swap and provide liquidity
                    swapAndLiquidify(amounToLiquidify);

                    if(autoLiquidityPool > amounToLiquidify) {
                        //lets substract the amount token for liquidity from pool
                        autoLiquidityPool = autoLiquidityPool.sub(amounToLiquidify);
                    } else {
                        autoLiquidityPool = 0;
                    }

                } //end if amounToLiquidify >= minAmountBeforeAutoLiuqidity

            } //end if sender is not uniswap pair

        }//end if auto liquidity is enabled

        uint256 sellTaxAmountSplit;

        // so here lets check if its sell, lets get the sell tax amount
        // burn half and add half to 
        if(txType == swapEngine.TX_SELL() && isSellTaxEnabled && sellTaxFee > 0) {
            
            uint256 sellTaxAmount = percentToAmount(sellTaxFee, amount);

            sellTaxAmountSplit = sellTaxAmount.div(2);

            // lets add to be burned
            autoBurnPool = autoBurnPool.add( sellTaxAmountSplit );
        }

          //compute amount for liquidity providers fund
        if(isHoldlersRewardEnabled && holdlersRewardFee > 0) {
           
            uint256 holdlersRewardAmount = percentToAmount(holdlersRewardFee, amount);

            // lets add half of the sell tax amount to reward pool
            holdlersRewardAmount  =  holdlersRewardAmount.add(sellTaxAmountSplit);

            //percentageOfRewardToReservedPool

            //if the holdlers rewards reserved pool is below what we want
            // assign all the rewards to the reserve pool, the reserved pool is used for
            // auto adjusting the rewards so that users wont get a decrease in rewards
            if( holdlersRewardReservedPool == 0 || 
                (holdlersRewardMainPool > 0 && getPercentageDiffBetweenReservedAndMainHoldersRewardsPools() <= minPercentageOfholdlersRewardReservedPoolToMainPool)
             ){
                holdlersRewardReservedPool = holdlersRewardReservedPool.add(holdlersRewardAmount);
            
            } else {

                // lets calculate the share of rewards for the the reserve pool
                uint256 reservedPoolRewardShare = percentToAmount(percentageShareOfHoldlersRewardsForReservedPool, holdlersRewardAmount);

                holdlersRewardReservedPool = holdlersRewardReservedPool.add(reservedPoolRewardShare);
                
                // set the main pool reward 
                holdlersRewardMainPool  = holdlersRewardMainPool.add(holdlersRewardAmount.sub(reservedPoolRewardShare));

            } //end if 

            totalRewardsTaken = totalRewardsTaken.add(holdlersRewardAmount);
    
        } //end if 

        /**
         * marketing and charity
         */
        if(isMarketingAndCharityEnabled && marketingAndCharityFee > 0) {
            // lets get marketing and charity amount to the address
            if( marketingAndCharityWallet != address(0) ){
                internalTransfer( 
                    address(this), 
                    marketingAndCharityWallet, 
                    percentToAmount(marketingAndCharityFee, amount), 
                    "MARKETING_&_DEV_FUNDS_TRANSFER_ERROR", 
                    false
                );
            }
        } //end if


        return amountMinusFee;
    } //end preprocess 


    ////////////////  HandleBuyBack /////////////////
    function handleBuyBack(address sender, uint256 amount, bytes32 _txType) private {

        ////////////////////// DEDUCT THE BUYBACK FEE ///////////////

        uint256 buyBackTokenAmount = percentToAmount( buyBackFee, amount);

        buyBackTokenPool = buyBackTokenPool.add(buyBackTokenAmount);

        if( buyBackTokenPool >= minAmountBeforeSellingTokenForBuyBack && _txType == swapEngine.TX_TRANSFER() ) {
            
            uint256 buyBackTokenSwapAmount = buyBackTokenPool;

            uint256 returnedETHValue = swapTokenForETH(buyBackTokenSwapAmount);

            buyBackETHPool = buyBackETHPool.add(returnedETHValue);

            if(buyBackTokenPool > buyBackTokenSwapAmount){
                buyBackTokenPool = buyBackTokenPool.sub(buyBackTokenSwapAmount);
            } else {
                buyBackTokenPool = 0; 
            }

        } ///end if 

        ///////////////////// END DEDUCT BUYBACK FEE ///////////////

        ///////////////////// START CHECKING IF BUYBACK IS POSSIBLE //////////////////

        //buyback is done gradually with the allocated funds
        if( remainingNumOfBuyBackForAllocatedFunds > 0 && allocatedFundsForBuyBack > 0 ) {

            remainingNumOfBuyBackForAllocatedFunds = remainingNumOfBuyBackForAllocatedFunds.sub(1);

            if( remainingNumOfBuyBackForAllocatedFunds == 0 ){
                allocatedFundsForBuyBack = 0;
            }

            // buyback and burn
            uint256 amountToBuyBackAndBurn = allocatedFundsForBuyBack.div( numOfBuyBackPerAllocatedFunds );

            //lets buy bnb and burn 
            uint256 totalTokensFromBuyBack = executeTokenBuyBack(amountToBuyBackAndBurn);

            // lets add the tokens to burn
            autoBurnPool = autoBurnPool.add(totalTokensFromBuyBack);

            // lets log
            buyBackTotalTokensBought = buyBackTotalTokensBought.add(totalTokensFromBuyBack);

           // total amount bought and burnt
           buyBackTotalTokensBoughtETH = buyBackTotalTokensBoughtETH.add(amountToBuyBackAndBurn);

        } else {

            ///////// LETS allocate funds for buyback ////////////////

            // here lets get the amount of bnb to be used for buy back
            if(buyBackETHPool > minAmountBeforeSellingBNBForBuyBack && sender != uniswapPair ) {

                uint256 bnbAmountToSell = buyBackETHPool;

                if(buyBackETHPool > bnbAmountToSell) {
                    buyBackETHPool = buyBackETHPool.sub(bnbAmountToSell);
                } else {
                    bnbAmountToSell = 0;
                }

                 // since we dont want to use all teh funds for buyback, we will split the bnb funds 
                // based on the value at buyBackBNBFundsSplitDivisor and use 1 part to buy back
                uint256 totalBnbForBuyBackAllocation = bnbAmountToSell.div( buyBackETHFundsSplitDivisor );


                // we will run buyback in a session, gradually buying back till the session runs out it own fund
                // lets allocate some funds for buyback
                allocatedFundsForBuyBack = allocatedFundsForBuyBack.add(totalBnbForBuyBackAllocation);

                remainingNumOfBuyBackForAllocatedFunds = numOfBuyBackPerAllocatedFunds;
            } //end if we need to allocate funds for buyback

        } //end if 

        ////////////////////////// END CHECKING IF BUYBACK IS POSSIBLE ///////////////////
    } //end handle 

    /**
    * @dev update holdlers account info, this info will be used for processing 
    * @param sender    the sendin account address
    * @param recipient the receiving account address
    */
    function updateHoldlersInfo(address sender, address recipient) private {

        //v2 we will use firstDepositTime, if the first time, lets set the initial deposit
        if(holdlersInfo[recipient].initialDepositTimestamp == 0){
            holdlersInfo[recipient].initialDepositTimestamp = block.timestamp;
        }

        // increment deposit count lol
        holdlersInfo[recipient].depositCount = holdlersInfo[recipient].depositCount.add(1);
        
        //if sender has no more tokens, lets remove his or data
        if(_balances[sender] == 0) {
            //user is no more holdling so we remove it
            delete holdlersInfo[sender];  
        }//end if 
        

    } //end process holdlEffect

    /**
     *  @dev release the acount rewards, this is called before transfer starts so that user will get the required amount to complete transfer
     *  @param _account the account to release the results to
     */
    function releaseAccountReward(address _account) private returns(bool) {

        //lets release sender's reward
        uint256 reward = getReward(_account);

        
        //dont bother processing if balance is 0
        if(reward == 0 || reward > holdlersRewardMainPool){
            return false;
        } 
        

        //lets deduct from our reward pool

        // now lets check if our reserve pool can cover that 
        if(holdlersRewardReservedPool >= reward) {
            
            // if the reward pool can cover that, deduct it from reserve 
            holdlersRewardReservedPool = holdlersRewardReservedPool.sub(reward);

        } else {
            
            // at this point, our reserve pool is down, so we deduct it from main pool
            holdlersRewardMainPool = holdlersRewardMainPool.sub(reward);

        }

        // credit user the reward
        _balances[_account] = _balances[_account].add(reward);

        //lets get account info 
        holdlersInfo[_account].totalRewardReleased =  holdlersInfo[_account].totalRewardReleased.add(reward);
        
        emit ReleaseAccountReward(_account, reward);

        return true;
    } //end function


    /**
     * internally transfer amount between two accounts
     * @param _from the sender of the amount
     * @param _to  the recipient of the amount
     * @param emitEvent wether to emit an event on succss or not  
     */
    function internalTransfer(address _from, address _to, uint256 _amount, string memory errMsg, bool emitEvent) private {

        //set from balance
        _balances[_from] = _balances[_from].sub(_amount, string(abi.encodePacked("CADA: INTERNAL_TRANSFER_SUB - ", errMsg)));

        //set _to Balance
        _balances[_to] = _balances[_to].add(_amount);

        if(emitEvent){
            emit Transfer(_from, _to, _amount); 
        }
    } //end internal transfer

    /**
     * @dev convert percentage value in Basis Point System to amount or token value
     * @param _percentInBps the percentage calue in basis point system
     * @param _amount the amount to be used for calculation
     * @return final value after calculation in uint256
     */
     function percentToAmount(uint256 _percentInBps, uint256 _amount) private pure returns(uint256) {
        //to get pbs,multiply percentage by 100
        return  (_amount.mul(_percentInBps)).div(10_000);
     }


    /**
     * @dev get max Tx Amount limit 
     * @return uint256  processed amount
     */
    function _getMaxTxAmontLimit() public view returns(uint256) {
        return percentToAmount(maxTxAmountLimitPercent, totalSupply());
    } //end fun 
    

    /**
     * @dev getPercentageOfReservedToMainRewardPool
     * @return uint256
     */
     function getPercentageDiffBetweenReservedAndMainHoldersRewardsPools() private view returns(uint256) {
        
        uint256 resultInPercent = ( holdlersRewardReservedPool.mul(100) ).div(holdlersRewardMainPool);

        // lets multiply by 100 to get the value in basis point system
        return (resultInPercent.mul(100));
     }

} //end contract