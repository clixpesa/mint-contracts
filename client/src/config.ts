import "dotenv/config";
import { writeFileSync } from "fs"
import { mnemonicToAccount, generateMnemonic, english } from "viem/accounts"
import { createBundlerClient, entryPoint07Address } from "viem/account-abstraction"
import { toSimpleSmartAccount } from "permissionless/accounts"
import { createPimlicoClient } from "permissionless/clients/pimlico"
import { createSmartAccountClient } from "permissionless"
import { Hex, createPublicClient, getContract, http } from "viem"

import { celo, celoAlfajores } from "viem/chains"

const mnemonic = (process.env.MNEMONIC) ?? ( () => {
  const phrase = generateMnemonic(english);
  writeFileSync(".env", `MNEMONIC=${phrase}`);
  return phrase;
})();

const apiKey = process.env.PIMLICO_API_KEY
if (!apiKey) throw new Error("Missing PIMLICO_API_KEY")
const thirdwebApiKey = process.env.THIRDWEB_API_KEY
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

export const account = await toSimpleSmartAccount({
	client: publicClient,
	owner: mnemonicToAccount(mnemonic),
	entryPoint: {
		address: entryPoint07Address,
		version: "0.7",
	},
})

export const accountClient = createSmartAccountClient({
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