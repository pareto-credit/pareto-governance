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

  error AddressZero();

  constructor(address _owner) Ownable(_owner) {}

  /// @notice Transfer tokens held by the contract to another address.
  /// @param token The address of the token contract.
  /// @param to The address to transfer tokens to.
  /// @param value The amount of tokens to transfer.
  /// @return bool Returns true on success.
  function transfer(address token, address to, uint256 value) external onlyOwner returns (bool) {
    if (token == address(0) || to == address(0)) revert AddressZero();
    IERC20(token).safeTransfer(to, value);
    return true;
  }

  /// @notice Transfer ETH held by the contract to another address.
  /// @param to The address to transfer ETH to.
  /// @param value The amount of ETH to transfer.
  /// @dev Reverts if the transfer fails.
  function transferETH(address payable to, uint256 value) onlyOwner external {
    if (to == address(0)) revert AddressZero();
    to.sendValue(value);
  }

  /// @notice Allow the contract to receive ETH.
  receive() external payable {}
}
