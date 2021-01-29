// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {RegistryAPI, VaultAPI} from "./BaseStrategy.sol";

contract MigrationWrapper {
    using SafeMath for uint256;

    ERC20 public token;

    // v2.registry.ychad.eth
    RegistryAPI constant registry = RegistryAPI(0xE15461B18EE31b7379019Dc523231C57d1Cbc18c);

    constructor(address _token) public {
        token = ERC20(_token);
    }

    function _latestVault() internal virtual view returns (VaultAPI) {
        return VaultAPI(registry.latestVault(address(token)));
    }

    function _activeVaults() internal virtual view returns (VaultAPI[] memory) {
        VaultAPI latest = _latestVault();
        uint256 num_deployments = registry.nextDeployment(address(token));
        VaultAPI[] memory vaults = new VaultAPI[](num_deployments);

        for (uint256 deployment_id = 0; deployment_id < num_deployments; deployment_id++) {
            VaultAPI vault = VaultAPI(registry.vaults(address(token), deployment_id));

            if (vault == latest) {
                break;
            }

            vaults[deployment_id] = vault;
        }

        return vaults;
    }

    function _migrate(address account) internal returns (uint256 migrated) {
        VaultAPI latest = _latestVault();
        VaultAPI[] memory vaults = _activeVaults();

        for (uint256 id = 0; id < vaults.length; id++) {
            uint256 shares = vaults[id].balanceOf(account);

            if (shares > 0 && vaults[id].allowance(account, address(this)) >= shares) {
                uint256 amount = vaults[id].withdraw(shares, address(this));
                migrated = migrated.add(latest.deposit(amount, account));
            }
        }
    }

    function migrate() external returns (uint256) {
        return _migrate(msg.sender);
    }

    function permitAll(VaultAPI[] calldata vaults, bytes[] calldata signatures) external {
        require(vaults.length == signatures.length);
        for (uint256 i = 0; i < vaults.length; i) {
            require(vaults[i].permit(msg.sender, address(this), uint256(-1), 0, signatures[i]));
        }
    }

    function deposit(uint256 amount) external returns (uint256) {
        VaultAPI vault = _latestVault();

        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(vault), amount);

        return vault.deposit(amount, msg.sender);
    }

    function withdraw(uint256 amount) external returns (uint256) {
        _migrate(msg.sender);
        VaultAPI vault = _latestVault();

        uint256 maxShares = amount.mul(vault.pricePerShare()).div(10**vault.decimals());
        return vault.withdraw(maxShares, msg.sender);
    }
}
