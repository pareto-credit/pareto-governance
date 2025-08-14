// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title A simple contract for holding funds.
 */
contract GovernableFund is Ownable {
  using Address for address payable;
  using SafeERC20 for IERC20;

  constructor(address _owner) Ownable(_owner) {}

  function transfer(address token, address to, uint256 value) external onlyOwner returns (bool) {
    require(token != address(0) && to != address(0), 'Address is 0');
    IERC20(token).safeTransfer(to, value);
    return true;
  }
  function transferETH(address payable to, uint256 value) onlyOwner external {
    require(to != address(0), 'Address is 0');
    to.sendValue(value);
  }

  receive() external payable {}
}