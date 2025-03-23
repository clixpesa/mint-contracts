import "dotenv/config";
import { mnemonicToAccount, generateMnemonic, english } from "viem/accounts"
import { setMnemonic, getMnemonic, setSmartAccount } from "./server";
import { Address, createPublicClient, getContract, http, parseEther, formatUnits } from "viem"
import { celo, celoAlfajores } from "viem/chains"
import { createSmartAccountClient } from "permissionless"
import { toSimpleSmartAccount } from "permissionless/accounts"
import { createPimlicoClient } from "permissionless/clients/pimlico"
import { stableTokenAbi } from "../contracts/ABIs/stableTokenABI";
import { getOverdraftDebt } from "../contracts/overdraft";

const apiKey = process.env.PIMLICO_API_KEY
const thirdwebApiKey = process.env.THIRDWEB_API_KEY
const entryPoint07Address = '0x0000000071727De22E5E9d8BAf0edAc6f37da032' as const


if (!apiKey) throw new Error("Missing PIMLICO_API_KEY")
if (!thirdwebApiKey) throw new Error("Missing THIRDWEB_API_KEY")

export const publicClient = createPublicClient({
    chain: celoAlfajores,
    transport: http(`https://44787.rpc.thirdweb.com/${thirdwebApiKey}`),
  });
  
export const pimlicoClient = createPimlicoClient({
    entryPoint: {
      address: entryPoint07Address,
      version: "0.7",
    },
    transport: http(`https://api.pimlico.io/v2/44787/rpc?apikey=${apiKey}`),
  })

export async function generateAndStoreMnemonic(userId: string): Promise<string> {
  const mnemonic = generateMnemonic(english);
  await setMnemonic(userId, mnemonic);
  return mnemonic;
}

export async function initializeAccount(userId: string) {
  
  const mnemonic = await getMnemonic(userId)
  const factoryAddress = "0xf56c3Ccc72540AfE01755479B5407e7Ee51080EF"

  if (!mnemonic) throw new Error('Mnemonic not found for user');

  const account = await toSimpleSmartAccount({
    client: publicClient,
    owner: mnemonicToAccount(mnemonic),
    entryPoint: {
      address: entryPoint07Address,
      version: "0.7",
    },
    factoryAddress,
  })
  
  const smartAccountClient = createSmartAccountClient({
    account,
    chain: celoAlfajores,
    bundlerTransport: http(`https://api.pimlico.io/v2/44787/rpc?apikey=${apiKey}`),
    paymaster: pimlicoClient,
    userOperation: {
      estimateFeesPerGas: async () => {
        return (await pimlicoClient.getUserOperationGasPrice()).fast
      },
    },
  })

  await setSmartAccount(userId, smartAccountClient.account.address)

  return smartAccountClient;
}

export async function getSmartAccount(userId: string) {
  try {
    // Check if user exists
    const mnemonic = await getMnemonic(userId);
    return initializeAccount(userId);
  } catch (error) {
    // If user doesn't exist, create a new smart account
    const mnemonic = await generateAndStoreMnemonic(userId);
    return initializeAccount(userId);
  }
}

export async function transferCelo(account: any, to: Address, value: string) {
  const txHash = await account.sendTransaction({
    to,
    value: parseEther(value),
  });
  return txHash;
}

export async function transferToken(params: {account: any, to: Address, amount: string, token: Address}) {
  const contract = getContract({
    address: params.token,
    abi: stableTokenAbi,
    client: {
      public: publicClient,
      wallet: params.account,
    },
  })
  const balance: bigint | any = await contract.read.balanceOf([params.account.account.address]);
  if(balance >= parseEther(params.amount)) {
    const txHash = await contract.write.transfer([params.to, parseEther(params.amount)])
    return txHash
  } else {
    return "0x"
  }

}