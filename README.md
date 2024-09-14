#  SHOP  Staking  Contract
[![Compile  &  Test  Pass](https://github.com/crypt0grapher/shop-staking/actions/workflows/ci.yml/badge.svg)](https://github.com/crypt0grapher/shop-staking/actions/workflows/ci.yml)

#  Usage
Set  up  bot  that  runs  `snapshot()`  function  every  24  hours  (epoch)  at  00:00  UTC  with  ether  on  it  (`msg.value`)

#  Description  
Stake  $SHOP  to  get  a  revenue  share  generated  by  $SHOP  Token  taxes  in  ETH

Once  one  stakes  N  $SHOP  they  got  N  $xSHOP  from  the  staking  contract.
The  rewards  are  generated  due  to  a  snapshot  of  Revenue  Share  Wallet  taken  every  epoch  (which  is  24  hours  currently,  the  snapshot  is  taken  at  midnight  UTC).
The  baseline  formula  is  pretty  straightforward:
The  amount  of  revenue  share  one  gets  =  (Staked  $SHOP  by  the  staker  /  Total  staked  $SHOP)  x  Revenue  Share  Wallet  fees.

There's  an  option  to  turn  on  auto  compounding  that  swaps  earned  revenue  share  in  ETH  into  $SHOP  and  re-stakes  the  generated  $SHOP  rewards.  This  happens  every  epoch  right  after  the  rewards  distribution.

In  reality,  the  algorithm  is  more  complex  since  it  accounts  for  the  time  of  staking,  earlier  distributed  rewards,  and  earlier  paid  fees.
The  algorithm  is  completely  transparent  and  sealed  in  the  staking  contract  ready  to  be  verified  by  anyone.
The  revenue  is  collected  at  midnight  (00:01    UTC)  on  Revenue  Share  Wallet  which  everyone  can  check.
Then,  23:59  later  at  00:00  UTC,  the  snapshot  of  staked  tokens  is  taken  -  the  amount  of  the  staked  $SHOP  for  every  participant  and  the  total  stake,  and  this  is  available  to  be  claimed  immediately.

Let's  consider  a  few  examples  with  increasing  complexity  to  illustrate  that.
A  participant  stakes  20K  $SHOP  on  4  Sep  without  auto-compounding,  then  claims  on  5  Sep.
Fees  generated  on  2  Sep  were  1  ETH,  so  starting  from  00:01  on  3  they  are  on  the  revenue  wallet.
On  4  Sep  the  snapshot  is  taken,  and  the  total  stake  is  100K  $SHOP.
Once  the  participant  claims,  they  got  1  ETH  X  20K/100K  =  0.2  ETH.

A  participant  stakes  20K  $SHOP  on  4  Sep  without  auto-compounding,  then  stakes  1000  $SHOP  on  5  Sep,  unstakes  (withdraws)  2000  $SHOP  on  6  Sep,  and  claims  on  7  Sep.
Fees  generated  by  the  token:  1  ETH  on  2  Sep  (claimable  4  Sep),  2  ETH  on  3  and  4  Sep  (claimable  5  and  6  Sep)
On  5  Sep  snapshot,  the  total  stake  is  120  $SHOP  and  on  6  Sep  it's  160  Shop
Once  the  participant  claims,  they  got  1  ETH  X  20K/100K  +  2  ETH  X  21K/120K    +  2  ETH  x  19K/160K=  0.2  +  0.35  +  0.2375  =  0.7875  ETH.

Now  with  autocompounding,  a  participant  stakes  20K  $SHOP  on  4  Sep  with  auto-compounding  and  claims  on  6  Sep.
The  price  of  $SHOP  at  midnight  UTC  on  5th  Sep  is  0.000005  WETH
Then  once  the  snapshot  is  taken  on  5th  Sep,  the  0.2  ETH  is  swapped  into  40K  $SHOP,    and  it  is  staked  automatically.
Then  next  day  midnight,  on  the  6th  when  the  snapshot  is  taken  it  accounts  thouse  amounts,  and  during  the  day  the  user  is  able  to    claim:
1  ETH  X  20K/100K  +  2  ETH  X  21K/120K  +    2  ETH  x  (19K+40K)/(160K+40K)  =    0.2  +  0.35  +  0.59  =    1.14  ETH

