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
  /// @param status New status of the allow-all flag
  event AllowAllSmartContractsUpdated(bool status);

  /// @notice Emitted when a smart wallet whitelist entry changes
  /// @param wallet Address of the smart contract wallet
  /// @param allowed New whitelist status of the smart contract wallet
  event SmartWalletStatusUpdated(address indexed wallet, bool allowed);

  /// @notice Emitted when a runtime code hash allowance is updated
  /// @param codeHash Runtime code hash
  /// @param allowed New allowance status of the runtime code hash
  event CodeHashStatusUpdated(bytes32 indexed codeHash, bool allowed);

  /// @param initialOwner Address that will control whitelist updates (multisig recommended)
  /// @param initialSmartWallets Addresses to whitelist at construction time
  /// @param initialAllowedCodeHashes Runtime code hashes to allow at construction time
  constructor(
    address initialOwner,
    address[] memory initialSmartWallets,
    bytes32[] memory initialAllowedCodeHashes
  ) Ownable(initialOwner) {
    uint256 walletLength = initialSmartWallets.length;
    for (uint256 i; i < walletLength; ++i) {
      address wallet = initialSmartWallets[i];
      if (wallet != address(0)) {
        smartWalletAllowed[wallet] = true;
        emit SmartWalletStatusUpdated(wallet, true);
      }
    }

    uint256 codeHashesLength = initialAllowedCodeHashes.length;
    for (uint256 i; i < codeHashesLength; ++i) {
      bytes32 codeHash = initialAllowedCodeHashes[i];
      if (codeHash != bytes32(0)) {
        allowedCodeHashes[codeHash] = true;
        emit CodeHashStatusUpdated(codeHash, true);
      }
    }
  }

  /// @notice Toggle the global allow-all flag
  /// @param status New status for the allow-all flag
  function setAllowAllSmartContracts(bool status) external onlyOwner {
    allowAllSmartContracts = status;
    emit AllowAllSmartContractsUpdated(status);
  }

  /// @notice Update whitelist status for a smart contract wallet
  /// @param wallet Address of the smart contract wallet
  /// @param allowed New whitelist status for the smart contract wallet
  function setSmartWalletStatus(address wallet, bool allowed) external onlyOwner {
    smartWalletAllowed[wallet] = allowed;
    emit SmartWalletStatusUpdated(wallet, allowed);
  }

  /// @notice Batch update whitelist status for multiple smart contract wallets
  /// @param wallets Addresses of the smart contract wallets
  /// @param allowed New whitelist status for the smart contract wallets
  function setSmartWalletStatuses(address[] calldata wallets, bool allowed) external onlyOwner {
    uint256 walletsLength = wallets.length;
    for (uint256 i; i < walletsLength; ++i) {
      address wallet = wallets[i];
      smartWalletAllowed[wallet] = allowed;
      emit SmartWalletStatusUpdated(wallet, allowed);
    }
  }

  /// @notice Update allowance status for a runtime code hash (e.g. Gnosis Safe proxy runtime)
  /// @param codeHash Runtime code hash to update
  /// @param allowed New allowance status for the runtime code hash
  function setCodeHashStatus(bytes32 codeHash, bool allowed) external onlyOwner {
    allowedCodeHashes[codeHash] = allowed;
    emit CodeHashStatusUpdated(codeHash, allowed);
  }

  /// @notice Implementation of the SmartWalletChecker interface used by VotingEscrow
  /// @param wallet Address of the smart contract wallet to check
  /// @return True if the wallet is allowed, false otherwise
  function check(address wallet) external view returns (bool) {
    return allowAllSmartContracts || smartWalletAllowed[wallet] || allowedCodeHashes[wallet.codehash];
  }
}
