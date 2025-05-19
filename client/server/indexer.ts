import "dotenv/config";
import {
	parseAbiItem,
	createPublicClient,
	http,
	Address,
	getContract,
	parseEther,
	formatUnits,
} from "viem";
import { celo, celoAlfajores } from "viem/chains";
import { users } from "./db.json";
import { getOverdraftDebt, getSmartAccount, repayOverdraft } from "../src";
import { stableTokenAbi } from "../src/contracts/ABIs/stableTokenABI";

const apiKey = process.env.PIMLICO_API_KEY;
const thirdwebApiKey = process.env.THIRDWEB_API_KEY;
const usdStable = "0x874069fa1eb16d44d622f2e0ca25eea172369bc1";
const localStable = "0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92";
const overdraftAddress = "0xaB6334966F6380F5736c7923De8Ef89b5E84d017";
let adminAccount: any = null;

if (!apiKey) throw new Error("Missing PIMLICO_API_KEY");
if (!thirdwebApiKey) throw new Error("Missing THIRDWEB_API_KEY");

export const publicClient = createPublicClient({
	chain: celoAlfajores,
	transport: http(`https://44787.rpc.thirdweb.com/${thirdwebApiKey}`),
});

(async () => {
	console.log("fetching admin acoount");
	try {
		adminAccount = await getSmartAccount("adminAccount");
		console.log(adminAccount.account.address);
	} catch (error) {
		console.log(error);
	}
})();

const localStableContract = getContract({
	address: localStable,
	abi: stableTokenAbi,
	client: publicClient,
});
const usdStableContract = getContract({
	address: usdStable,
	abi: stableTokenAbi,
	client: publicClient,
});

const unwatch = publicClient.watchEvent({
	address: [usdStable, localStable],
	event: parseAbiItem(
		"event Transfer(address indexed from, address indexed to, uint256 value)",
	),
	args: {
		to: "0x81213104BbC7d15E0a7044F4F8354c0B2E46465c", //users.map((user) => user.address as Address),
	},
	onLogs: (logs) => checkForOverdraft(logs),
});

async function checkForOverdraft(events: any) {
	events.forEach(
		async (log: { args: { from: string; to: string; value: bigint } }) => {
			if (log.args.from == overdraftAddress) {
				console.log(`UsedOverdraft | ${log.args.to}`);
			} else {
				const cKESBalance: any = await localStableContract.read.balanceOf([
					log.args.to,
				]);
				const cUSDBalance: any = await usdStableContract.read.balanceOf([
					log.args.to,
				]);
				let overdraftDebt = await getOverdraftDebt(log.args.to as Address);
				if (cKESBalance > parseEther("1")) {
					await repayOverdraft({
						account: adminAccount,
						userAddress: log.args.to as Address,
						token: localStable,
						amount:
							overdraftDebt.amountDue > cKESBalance
								? formatUnits(cKESBalance, 18)
								: formatUnits(overdraftDebt.amountDue, 18),
					});
					overdraftDebt = await getOverdraftDebt(log.args.to as Address);
					console.log("Paid Overdraft with CKES");
				}

				if (cUSDBalance > parseEther("0.01")) {
					await repayOverdraft({
						account: adminAccount,
						userAddress: log.args.to as Address,
						token: usdStable,
						amount:
							overdraftDebt.amountDue > Number(cUSDBalance) * 128
								? formatUnits(cUSDBalance, 18)
								: formatUnits(
										BigInt(Number(overdraftDebt.amountDue) / 128),
										18,
									),
					});

					console.log("Paid Overdraft with CUSD");
				}
			}
		},
	);
}
