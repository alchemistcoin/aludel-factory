import { TypedDataField } from "@ethersproject/abstract-signer";
import { parseEther } from "@ethersproject/units";
import { BigNumberish, Contract, Wallet } from "ethers";

import { EthereumProvider } from "hardhat/types";

export async function takeSnapshot(provider: EthereumProvider) {
  return (await provider.request({
    method: "evm_snapshot",
  })) as string;
}

export async function revert(provider: EthereumProvider, snapshotId: string) {
  await provider.request({
    method: "evm_revert",
    params: [snapshotId],
  });
}

export async function getProvider(
  provider?: EthereumProvider
): Promise<EthereumProvider> {
  if (provider !== undefined) {
    return provider;
  }

  const hre = await import("hardhat");
  return hre.network.provider;
}

export function wrapWithTitle(title: string | undefined, str: string) {
  if (title === undefined) {
    return str;
  }

  return `${title} at step "${str}"`;
}

const DAY = 60 * 60 * 24;

export const ETHER: (a: number) => BigNumberish = (amount = 1) =>
  parseEther(amount.toString());
export const DAYS = (days = 1) => days * DAY;

export const signPermission = async (
  method: string,
  vault: Contract,
  owner: Wallet,
  delegateAddress: string,
  tokenAddress: string,
  amount: BigNumberish,
  vaultNonce?: BigNumberish,
  chainId?: BigNumberish
) => {
  // get nonce
  if (vaultNonce === undefined) {
    vaultNonce = await vault.getNonce();
  }
  // vaultNonce = vaultNonce //|| (await vault.getNonce())
  // get chainId
  chainId = chainId || (await vault.provider.getNetwork()).chainId;
  // craft permission
  const domain = {
    name: "UniversalVault",
    version: "1.0.0",
    chainId,
    verifyingContract: vault.address,
  };
  const types = {} as Record<string, TypedDataField[]>;
  types[method] = [
    { name: "delegate", type: "address" },
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ];
  const value = {
    delegate: delegateAddress,
    token: tokenAddress,
    amount,
    nonce: vaultNonce,
  };
  // sign permission
  const signedPermission = await owner._signTypedData(domain, types, value);
  // return
  return signedPermission;
};

/**
 * ThisMocha helper reverts all your state modifications in an `after` hook.
 *
 * @param title A title that's included in all the hooks that this helper uses.
 * @param provider The network provider.
 */
export function revertAfter(title?: string, provider?: EthereumProvider) {
  let snapshotId: string | undefined;
  before(
    wrapWithTitle(title, "resetAfter: taking snapshot"),
    async function () {
      snapshotId = await takeSnapshot(await getProvider(provider));
    }
  );

  after(wrapWithTitle(title, "resetAfter: reverting state"), async function () {
    if (snapshotId !== undefined) {
      await revert(await getProvider(provider), snapshotId);
    }
  });
}
