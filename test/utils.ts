import { TypedDataField } from '@ethersproject/abstract-signer'
import { parseEther } from '@ethersproject/units';
import { BigNumber, BigNumberish, BytesLike, Contract, Signer, Wallet } from 'ethers'

const DAY = 60 * 60 * 24

export const ETHER = (amount: number = 1) => parseEther(amount.toString());
export const DAYS = (days: number = 1) => days * DAY;

export const signPermission = async (
    method: string,
    vault: Contract,
    owner: Wallet,
    delegateAddress: string,
    tokenAddress: string,
    amount: BigNumberish,
    vaultNonce?: BigNumberish,
    chainId?: BigNumberish,
  ) => {
    // get nonce
    if (vaultNonce === undefined) {
        vaultNonce = await vault.getNonce()
    }
    // vaultNonce = vaultNonce //|| (await vault.getNonce())
    // get chainId
    chainId = chainId || (await vault.provider.getNetwork()).chainId
    // craft permission
    const domain = {
      name: 'UniversalVault',
      version: '1.0.0',
      chainId,
      verifyingContract: vault.address,
    }
    const types = {} as Record<string, TypedDataField[]>
    types[method] = [
      { name: 'delegate', type: 'address' },
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
    ]
    const value = {
      delegate: delegateAddress,
      token: tokenAddress,
      amount,
      nonce: vaultNonce,
    }
    // sign permission
    const signedPermission = await owner._signTypedData(domain, types, value)
    // return
    return signedPermission
  }
  