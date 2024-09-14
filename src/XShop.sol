//  SPDX-License-Identifier:  MIT
pragma  solidity  ^0.8.21;

import  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import  "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import  "@openzeppelin/contracts/access/Ownable.sol";
import  "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import  "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import  "./IXShop.sol";

///  @title  Shop  Bot  Staking  Contract
///  @notice  This  contract  allow  users  to  stake  SHOP  tokens  and  earn  rewards  from  the  fees  generated  by  the  platform

contract  XShop  is  IXShop,  ERC20("Staked  Shop  Bot",  "xSHOP"),  Ownable,  ReentrancyGuard  {

        IERC20  public  constant  shopToken  =  IERC20(0x99e186E8671DB8B10d45B7A1C430952a9FBE0D40);
        IUniswapV2Router02  public  constant  uniswapRouter  =  IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        uint256  public  constant  epochDuration  =  1  days;

        uint256  public  minimumStake  =  20000  *  1e18;
        //  Staking  time  lock,  5  days  by  default
        uint256  public  timeLock  =  5  days;
        //  Total  rewards  injected
        uint256  public  totalRewards;

        //  Snapshot  of  the  epoch,  generated  by  the  snapshot(),  used  to  calculate  rewards
        struct  EpochInfo  {
                //  Snapshot  time
                uint256  timestamp;
                //  Rewards  injected
                uint256  rewards;
                //  Total  deposited  snap
                uint256  supply;
                //  $SHOP  swapped  for  rewards  for  re-investors
                uint256  shop;
                //  This  is  used  for  aligning  with  the  user  deposits/withdrawals  during  epoch  to  adjust  totalsupply
                uint256  deposited;
                uint256  withdrawn;
        }

        uint256  public  currentEpoch;
        mapping(uint256  =>  EpochInfo)  public  epochInfo;

        //  User  info,  there's  also  a  balance  of  xSHOP  on  the  ERC20  super  contract
        struct  UserInfo  {
                //epoch  =>  total  amount  deposited  during  the  epoch
                mapping(uint256  =>  uint256)  depositedInEpoch;
                mapping(uint256  =>  uint256)  withdrawnInEpoch;
                mapping(uint256  =>  bool)  isReinvestingOnForEpoch;
                //  a  starting  epoch  for  reward  calculation  for  user  -  either  last  claimed  or  first  deposit
                uint256  lastEpochClaimedOrReinvested;
                uint256  firstDeposit;
        }

        mapping(address  =>  UserInfo)  public  userInfo;

        //  That's  for  enumerating  re-investors  because  we  have  to  iterate  over  them  to  buy  SHOP  for  rewards  generated
        uint256  public  reInvestorsCount;
        mapping(address  =>  uint256)  public  reInvestorsIndex;
        mapping(uint256  =>  address)  public  reInvestors;

        //  ==========  Configuration  ==========
        constructor()  ReentrancyGuard()    {
        }

        function  setMinimumStake(uint256  _minimumStake)  public  onlyOwner  {
                minimumStake  =  _minimumStake;
        }

        function  setTimeLock(uint256  _timeLock)  public  onlyOwner  {
                timeLock  =  _timeLock;
        }

        //  ==========  State  changing  ==========

        function  deposit(uint256  _amount)  public  nonReentrant  {
                require(_amount  +  balanceOf(msg.sender)  >=  minimumStake,  "Minimum  deposit  is  20K  $SHOP");
                require(shopToken.transferFrom(msg.sender,  address(this),  _amount),  "Transfer  failed");

                if  (userInfo[msg.sender].firstDeposit  ==  0)  {
                        userInfo[msg.sender].firstDeposit  =  block.timestamp;
                }
                _updateStake(msg.sender,  _amount,  true);

                emit  Deposited(msg.sender,  _amount);
        }

        function  withdraw(uint256  _amount)  public  nonReentrant  {
                require(balanceOf(msg.sender)  >=  _amount,  "Insufficient  balance");
                require(userInfo[msg.sender].firstDeposit  +  timeLock  <  block.timestamp,  "Too  early  to  withdraw");

                _updateStake(msg.sender,  _amount,  false);

                require(shopToken.transfer(msg.sender,  _amount),  "Transfer  failed");

                emit  Withdrawn(msg.sender,  _amount);
        }

        function  claimReward()  public  nonReentrant  {
                require(currentEpoch  >  1,  "No  rewards  have  been  distributed  yet");
//                uint256  lastSnapshotTime  =  epochInfo[currentEpoch  -  1].timestamp;
//                require(lastSnapshotTime  +  epochDuration  <=  block.timestamp,  "Too  early  to  calculate  rewards");
                require(!isReinvesting(),  "Auto-compounding  is  enabled");

                uint256  reward  =  getPendingReward();
                require(reward  >  0,  "No  reward  available");
                require(address(this).balance  >=  reward,  "Insufficient  contract  balance  to  transfer  reward");
                payable(msg.sender).transfer(reward);
                userInfo[msg.sender].lastEpochClaimedOrReinvested  =  currentEpoch  -  1;
                emit  Claimed(msg.sender,  reward);
        }

        //  we  need  it  to  be  only  owner  to  keep  epochs  precise
        function  snapshot()  public  payable  nonReentrant  onlyOwner  {
                require(msg.value  >  0,  "ETH  amount  must  be  greater  than  0");
                uint256  lastSnapshotTime  =  0;
                if  (currentEpoch  >  0)  {
                        lastSnapshotTime  =  epochInfo[currentEpoch  -  1].timestamp;
                        require(block.timestamp  >=  lastSnapshotTime  +  epochDuration  -  5  minutes,  "Too  early  for  a  new  snapshot");
                }
                totalRewards  +=  msg.value;



                epochInfo[currentEpoch].rewards  =  msg.value;
                epochInfo[currentEpoch].timestamp  =  block.timestamp;
                epochInfo[currentEpoch].supply  =  totalSupply();
                //  swap  ETH  for  autocompounding


                uint256  ethToSell  =  0;
                uint256[]  memory  stakersRewarsInEpoch  =  new  uint256[](reInvestorsCount  +  1);
                for  (uint256  i  =  1;  i  <=  reInvestorsCount;  i++)  {
                        address  user  =  reInvestors[i];
                        userInfo[user].isReinvestingOnForEpoch[currentEpoch]  =  true;

                        stakersRewarsInEpoch[i]  =  _calculateReward(user,  true);
                        ethToSell  +=  stakersRewarsInEpoch[i];
                        if  (ethToSell  >  0)  {
                                userInfo[user].lastEpochClaimedOrReinvested  =  currentEpoch;
                        }
                }
                uint256  xShopToMintTotal  =  0;

                if  (ethToSell  >  0)  {
                        xShopToMintTotal  =  _swapEthForShop(ethToSell);
                        epochInfo[currentEpoch].shop  =  xShopToMintTotal;

                        //now  updating  staking  balances
                        for  (uint256  i  =  1;  i  <=  reInvestorsCount;  i++)  {

                                uint256  xShopToMint  =  stakersRewarsInEpoch[i]  *  xShopToMintTotal  /  ethToSell;
                                _updateStake(msg.sender,  xShopToMint,  true);
                        }
                }
                emit  Snapshot(currentEpoch,  msg.value,  msg.sender);
                currentEpoch++;
        }


        function  toggleReinvesting()  public  {
                bool  currentStatus  =  reInvestorsIndex[msg.sender]  >  0;
                if  (!currentStatus)  {
                        //  Add  re-investor  to  the  renumeration
                        if  (reInvestorsIndex[msg.sender]  ==  0)  {
                                reInvestorsCount++;
                                reInvestorsIndex[msg.sender]  =  reInvestorsCount;
                                reInvestors[reInvestorsCount]  =  msg.sender;
                                userInfo[msg.sender].isReinvestingOnForEpoch[currentEpoch]  =  true;
                        }
                }
                else  {
                        //  Remove  re-investor  from  the  renumeration
                        if  (reInvestorsIndex[msg.sender]  !=  0)  {
                                uint256  index  =  reInvestorsIndex[msg.sender];
                                address  lastReinvestor  =  reInvestors[reInvestorsCount];

                                //  Swap  the  msg.sender  to  remove  with  the  last  msg.sender
                                reInvestors[index]  =  lastReinvestor;
                                reInvestorsIndex[lastReinvestor]  =  index;

                                //  Remove  the  last  msg.sender  and  update  count
                                delete  reInvestors[reInvestorsCount];
                                delete  reInvestorsIndex[msg.sender];
                                reInvestorsCount--;
                                userInfo[msg.sender].isReinvestingOnForEpoch[currentEpoch]  =  false;
                        }
                }
                emit  Reinvestment(msg.sender,  !currentStatus);
        }


        function  rescueETH(uint256  _weiAmount)  external  {
                payable(owner()).transfer(_weiAmount);
        }

        function  rescueERC20(address  _tokenAdd,  uint256  _amount)  external  {
                IERC20(_tokenAdd).transfer(owner(),  _amount);
        }

        //  ==========  View  functions  ==========

        function  getPendingReward()  public  view  returns  (uint256)  {
                return  calculateRewardForUser(msg.sender);
        }

        function  calculateRewardForUser(address  user)  public  view  returns  (uint256)  {
                return  _calculateReward(user,  false);
        }

        function  isReinvesting()  public  view  returns  (bool)  {
                return  reInvestorsIndex[msg.sender]  >  0;
        }

        //  ==========  Internal  functions  ==========

        function  _updateStake(address  _user,  uint256  _amount,  bool  _isDeposit)  internal  {
                if  (_isDeposit)  {
                        userInfo[_user].depositedInEpoch[currentEpoch]  +=  _amount;
                        epochInfo[currentEpoch].deposited  +=  _amount;
                        _mint(_user,  _amount);
                }  else  {
                        userInfo[_user].withdrawnInEpoch[currentEpoch]  +=  _amount;
                        epochInfo[currentEpoch].withdrawn  +=  _amount;
                        _burn(_user,  _amount);
                }
        }


        function  _swapEthForShop(uint256  _ethAmount)  internal  returns  (uint256)  {
                address[]  memory  path  =  new  address[](2);
                path[0]  =  uniswapRouter.WETH();
                path[1]  =  address(shopToken);

                //  15  seeconds  from  the  current  block  time
                uint256  deadline  =  block.timestamp  +  15;

                //  Swap  and  return  the  amount  of  SHOP  tokens  received
                uint[]  memory  amounts  =  uniswapRouter.swapExactETHForTokens{value:  _ethAmount}(
                        0,  //  Accept  any  amount  of  SHOP
                        path,
                        address(this),
                        deadline
                );
                emit  Swapped(_ethAmount,  amounts[1]);
                //  Return  the  amount  of  SHOP  tokens  received
                return  amounts[1];
        }

//  Mock  function  for  demonstration  purposes.  In  reality,  you'd  interact  with  a  decentralized  exchange  contract  here.
        function  _calculateReward(address  _user,  bool  _isForReinvestment)  internal  view  returns  (uint256)  {

                uint256  reward  =  0;
                if  (currentEpoch  <  1)  {
                        return  0;
                }
                uint256  userBalanceInEpoch  =  balanceOf(_user);
                uint256  i  =  currentEpoch;
                while  (i  >=  userInfo[_user].lastEpochClaimedOrReinvested  &&  i  <=  currentEpoch)  {
                        uint256  supplyInEpoch  =  epochInfo[i].supply;
                        uint256  epochReward  =  supplyInEpoch  ==  0  ||  i  >=  currentEpoch  -  1  ?  0  :
                                userBalanceInEpoch  *  epochInfo[i].rewards  /  supplyInEpoch;


                        if  (epochReward  >  0  &&
                                (_isForReinvestment  &&  reInvestorsIndex[_user]  >  0  ||
                                        !_isForReinvestment  &&  !userInfo[_user].isReinvestingOnForEpoch[i]))  {
                                reward  +=  epochReward;

                        }


                        if  (i  ==  0)  {
                                break;
                        }
                        userBalanceInEpoch  -=  userInfo[_user].depositedInEpoch[i];
                        userBalanceInEpoch  +=  userInfo[_user].withdrawnInEpoch[i];
                        i--;
                }
                return  reward;
        }

        function  _beforeTokenTransfer(address  _from,  address  _to,  uint256  _amount)  internal  override  {
                super._beforeTokenTransfer(_from,  _to,  _amount);
                require(_from  ==  address(0)  ||  _to  ==  address(0),  "Only  stake  or  unstake");
        }

        receive()  external  payable  {}

}
