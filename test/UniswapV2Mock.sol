// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Simple ERC20 Interface
interface IERC20Mock {
    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function mint(address to, uint256 amount) external;
}

contract UniswapV2Mock {
    event Swapped(address indexed user, uint256 ethAmount, uint256 tokenAmount);
    // Fallback function to allow receiving ETH
    receive() external payable {}

    // Mock swapExactETHForTokens function
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
    external
    payable
    returns (uint256[] memory amounts)
    {
        require(path[0] == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), "UniswapV2Mock: Invalid path");
        require(path[path.length - 1] == address(0x99e186E8671DB8B10d45B7A1C430952a9FBE0D40), "UniswapV2Mock: Invalid last token");
        require(block.timestamp <= deadline, "UniswapV2Mock: Deadline exceeded");
        require(msg.value > 0, "UniswapV2Mock: Invalid msg.value");

        //predefined 100K shop for 1 eth
        uint256 tokenAmount = msg.value * 100000;
        require(tokenAmount >= amountOutMin, "UniswapV2Mock: Slippage not acceptable");
        IERC20Mock token = IERC20Mock(0x99e186E8671DB8B10d45B7A1C430952a9FBE0D40);
        // Simulate token transfer
        require(token.transfer(to, tokenAmount), "UniswapV2Mock: Transfer failed");

        emit Swapped(msg.sender, msg.value, tokenAmount);

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        amounts[path.length - 1] = tokenAmount;

        return amounts;
    }

    function WETH() external pure returns (address) {
        return address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }
}
