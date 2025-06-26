pragma solidity 0.4.16;

import "../../src/2021/04.SingleOwnerGuard.sol";
import "../../src/2021/04.GuardRegistry.sol";
import "../../src/2021/04.Vault.sol";

contract Setup {
    GuardRegistry public registry;
    Vault public vault;

    function Setup() public {
        registry = new GuardRegistry();
        registry.registerGuardImplementation(new SingleOwnerGuard(), true);

        vault = new Vault(registry);

        SingleOwnerGuard guard = SingleOwnerGuard(vault.guard());
        guard.addPublicOperation("deposit");
        guard.addPublicOperation("withdraw");
    }

    function isSolved() public view returns (bool) {
        return vault.owner() != address(this);
    }
}
