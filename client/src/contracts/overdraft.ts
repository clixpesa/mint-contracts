import {
	parseAbi,
	parseEther,
	type Address,
	type Hex,
	getContract,
	formatUnits,
} from "viem";
import { overdraftAbi } from "./ABIs/overdraftABI";
import { stableTokenAbi } from "./ABIs/stableTokenABI";
import { publicClient } from "../core/account";

const overdraftAddress = "0xaB6334966F6380F5736c7923De8Ef89b5E84d017";
const usdStable = "0x874069fa1eb16d44d622f2e0ca25eea172369bc1";
const localStable = "0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92";

type SubscribeUserParams = {
	account: any;
	userAddress: Address;
	initialLimit: string;
	key?: string;
};

type OverdraftParams = {
	account: any;
	userAddress: Address;
	token: Address;
	amount: string;
};

type TransferWithOverdraftParams = {
	account: any;
	from: Address;
	to: Address;
	token: Address;
	amount: string;
};

export async function subscribeToOverdraft(
	params: SubscribeUserParams,
): Promise<Hex> {
	//Run approvals
	let txHash = "0x" as Hex;
	try {
		await params.account.writeContract({
			address: usdStable,
			abi: parseAbi([
				"function approve(address spender, uint256 amount) public returns (bool)",
			]),
			functionName: "approve",
			args: [overdraftAddress, parseEther(params.initialLimit)],
		});
		await params.account.writeContract({
			address: localStable,
			abi: parseAbi([
				"function approve(address spender, uint256 amount) public returns (bool)",
			]),
			functionName: "approve",
			args: [
				overdraftAddress,
				parseEther((Number(params.initialLimit) * 130).toString()),
			],
		});
		txHash = await params.account.writeContract({
			address: overdraftAddress,
			abi: overdraftAbi,
			functionName: "subscribeUser",
			args: [params.userAddress, parseEther(params.initialLimit), "CPODTest"],
		});
		return txHash;
	} catch (error) {
		console.error("Error in subscribing user:", error);
		return txHash;
	}
}

export async function useOverdraft(params: OverdraftParams): Promise<Hex> {
	const txHash = await params.account.writeContract({
		address: overdraftAddress,
		abi: overdraftAbi,
		functionName: "useOverdraft",
		args: [params.userAddress, params.token, parseEther(params.amount)],
	});
	return txHash;
}

export async function repayOverdraft(params: OverdraftParams): Promise<Hex> {
	const txHash = await params.account.writeContract({
		address: overdraftAddress,
		abi: overdraftAbi,
		functionName: "repayOverdraft",
		args: [params.userAddress, params.token, parseEther(params.amount)],
	});
	return txHash;
}

export async function transferTokenWithOverdraft(
	params: TransferWithOverdraftParams,
) {
	const tokenContract = getContract({
		address: params.token,
		abi: stableTokenAbi,
		client: {
			public: publicClient,
			wallet: params.account,
		},
	});
	const balance: bigint | any = await tokenContract.read.balanceOf([
		params.from,
	]);
	const deficit = parseEther(params.amount) - balance;
	try {
		await useOverdraft({
			account: params.account,
			userAddress: params.from,
			token: params.token,
			amount: formatUnits(deficit, 18),
		});
	} catch (error) {
		console.log("Overdraft Request Failed", error);
	} finally {
		const txHash = await tokenContract.write.transfer([
			params.to,
			parseEther(params.amount),
		]);
		return txHash;
	}
}

export async function getOverdraftDebt(user: Address) {
	const contract = getContract({
		address: overdraftAddress,
		abi: overdraftAbi,
		client: publicClient,
	});

	const thisUser: any = await contract.read.getUser([user]);
	const overdraftDebt = thisUser.overdraftDebt;
	return overdraftDebt;
}
