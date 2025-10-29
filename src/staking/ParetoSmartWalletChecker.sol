// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ParetoSmartWalletChecker
/// @notice Whitelist registry used by VotingEscrow to allow specific smart contracts to lock BPT
/// @dev Implements the SmartWalletChecker interface expected by ve8020 VotingEscrow contracts
contract ParetoSmartWalletChecker is Ownable {
  /// @notice Tracks whether a smart contract address is allowed to interact with VotingEscrow
  mapping(address => bool) private smartWalletAllowed;

  /// @notice Flag allowing every smart contract when set to true
  bool public allowAllSmartContracts;

  /// @notice Tracks runtime code hashes that are implicitly allowed (e.g. Gnosis Safe proxies)
  mapping(bytes32 => bool) public allowedCodeHashes;

  /// @notice Emitted when the allow-all flag changes
  /// @param status New value applied to the allow-all flag
  event AllowAllSmartContractsUpdated(bool status);

  /// @notice Emitted when a smart wallet whitelist entry changes
  /// @param wallet Smart contract wallet address that was updated
  /// @param allowed Whether the wallet is now allowed
  event SmartWalletStatusUpdated(address indexed wallet, bool allowed);

  /// @notice Emitted when a runtime code hash allowance is updated
  /// @param codeHash Runtime code hash that was updated
  /// @param allowed Whether the hash is now allowed
  event CodeHashStatusUpdated(bytes32 indexed codeHash, bool allowed);

  /// @param initialOwner Address that will control whitelist updates (multisig recommended)
  constructor(address initialOwner) Ownable(initialOwner) {
    allowedCodeHashes[initialOwner.codehash] = true;
  }

  /// @notice Toggle the global allow-all flag
  /// @dev Callable only by the contract owner
  /// @param status True to allow every smart contract, false to rely on explicit whitelisting
  function setAllowAllSmartContracts(bool status) external onlyOwner {
    allowAllSmartContracts = status;
    emit AllowAllSmartContractsUpdated(status);
  }

  /// @notice Update whitelist status for a smart contract wallet
  /// @dev Callable only by the contract owner
  /// @param wallet Smart contract address whose status is being set
  /// @param allowed True to whitelist the wallet, false to remove it
  function setSmartWalletStatus(address wallet, bool allowed) external onlyOwner {
    smartWalletAllowed[wallet] = allowed;
    emit SmartWalletStatusUpdated(wallet, allowed);
  }

  /// @notice Batch update whitelist status for multiple smart contract wallets
  /// @dev Callable only by the contract owner
  /// @param wallets Smart contract addresses whose status is being set
  /// @param allowed True to whitelist the wallets, false to remove them
  function setSmartWalletStatuses(address[] calldata wallets, bool allowed) external onlyOwner {
    uint256 walletsLength = wallets.length;
    for (uint256 i; i < walletsLength; i++) {
      address wallet = wallets[i];
      smartWalletAllowed[wallet] = allowed;
      emit SmartWalletStatusUpdated(wallet, allowed);
    }
  }

  /// @notice Update allowance status for a runtime code hash (e.g. Gnosis Safe proxy runtime)
  /// @dev Callable only by the contract owner
  /// @param codeHash Runtime code hash to update
  /// @param allowed True to allow all contracts with this runtime hash, false to remove it
  function setCodeHashStatus(bytes32 codeHash, bool allowed) external onlyOwner {
    allowedCodeHashes[codeHash] = allowed;
    emit CodeHashStatusUpdated(codeHash, allowed);
  }

  /// @notice Implementation of the SmartWalletChecker interface used by VotingEscrow
  /// @param wallet Smart contract address attempting to interact with VotingEscrow
  /// @return True when the wallet is permitted to lock tokens
  function check(address wallet) external view returns (bool) {
    return allowAllSmartContracts || smartWalletAllowed[wallet] || allowedCodeHashes[wallet.codehash];
  }
}
