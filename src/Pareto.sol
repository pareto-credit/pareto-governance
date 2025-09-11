// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title Pareto (PAR) ERC20 token
/// @notice Governance token of the Pareto ecosystem
/// @dev Token is timestamp-based for voting snapshots (see IERC6372)
contract Pareto is ERC20, ERC20Permit, ERC20Votes {
  /// @notice Initial supply of 18.2 million PAR
  constructor() ERC20("Pareto", "PAR") ERC20Permit("Pareto") {
    _mint(msg.sender, 18_200_000 * 10**18);
  }

  /// @notice Current clock time used for voting snapshots
  /// @dev Overrides IERC6372 functions to make the token & governor timestamp-based
  function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
  }

  /// @notice Clock mode used for voting snapshots
  /// @return string describing the clock mode
  // solhint-disable-next-line func-name-mixedcase
  function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
  }

  /// @notice See {ERC20-_update}.
  /// @dev The functions below are overrides required by Solidity.
  /// @param from address tokens are moved from
  /// @param to address tokens are moved to
  /// @param amount of tokens moved
  function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
    super._update(from, to, amount);
  }

  /// @notice See {IERC20Permit-nonces}.
  /// @param owner address to query
  /// @return the current nonce for `owner`
  function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
    return super.nonces(owner);
  }
}