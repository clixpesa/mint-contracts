import { parseAbi, parseEther, type Address, type Hex} from "viem";
import { type SmartAccountClient } from "permissionless";
import { overdraftAbi } from "./ABIs/overdraftABI";

const overdraftAddress = "0xcFD758386a912ca83cbbA38A33272f5F8A5B55c9"
const usdStable = "0x874069fa1eb16d44d622f2e0ca25eea172369bc1"
const localStable = "0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92"

type SubscribeUserParams = {
  account: any, 
  userAddress: Address, 
  initialLimit: string,
  key?: string
}

type OverdraftParams = {
  account: any,
  userAddress: Address, 
  token: Address,
  amount: string
}

export async function subscribeToOverdraft(params: SubscribeUserParams):Promise<Hex>{
  //Run approvals 
  let txHash = "0x" as Hex
  try{
    /*await params.account.writeContract({
      address: usdStable,
      abi: parseAbi(['function approve(address spender, uint256 amount) public returns (bool)']),
      functionName: "approve",
      args: [overdraftAddress, parseEther(params.initialLimit)]
    })
    await params.account.writeContract({
      address: localStable,
      abi: parseAbi(['function approve(address spender, uint256 amount) public returns (bool)']),
      functionName: "approve",
      args: [overdraftAddress, parseEther((Number(params.initialLimit) * 130).toString())]
    })*/
    txHash = await params.account.writeContract({
      address: overdraftAddress,
      abi: parseAbi(["function subscribeUser(address user, uint256 initialLimit, string memory key) external"]),
      functionName: "subscribeUser",
      args: [params.userAddress, parseEther(params.initialLimit), "CPODTest"]
    }) 
  }catch(error){
    console.error('Error in subscribing user:', error);
    return txHash
  }finally {
    return txHash
  }
}

export async function useOverdraft(params: OverdraftParams):Promise<Hex> {
  const txHash = await params.account.writeContract({
    address: overdraftAddress,
    abi: overdraftAbi,
    functionName: "useOverdraft",
    args: [params.userAddress, params.token, parseEther(params.amount), ]
  })
  return txHash
}

export async function repayOverdraft(params: OverdraftParams):Promise<Hex> {
  const txHash = await params.account.writeContract({
    address: overdraftAddress,
    abi: overdraftAbi,
    functionName: "repayOverdraft",
    args: [params.userAddress, params.token, parseEther(params.amount), ]
  })
  return txHash
}

