import * as readline from 'readline';
import {
  getSmartAccount,
  transferToken,
  subscribeToOverdraft,
  transferTokenWithOverdraft,
  getOverdraftDebt,
} from "./src"
import { formatUnits } from 'viem';


// Create a readline interface
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

// Function to pause and wait for input
function waitForInput(question: string): Promise<string> {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer);
    });
  });
}

async function main() {
  const userId = 'user00003';

  // Create a smart account:
  console.log("Clixpesa AA and Overdraft Demo\n============")
  await waitForInput('PressEnter to continue...');
  console.log("\nCreating an Account...\n")
  const smartAccount = await getSmartAccount(userId);
  console.log(`smartAccount: ${smartAccount.account.address}`)
  await waitForInput('Top up account then press Enter to continue...');

  // Transfer a token with zero gas
  console.log("\nTransfering a token with Zero Gas...\n")
  const tokenTranferHash = await transferToken({
    account: smartAccount,
    to: "0x8E912eE99bfaECAe8364Ba6604612FfDfE46afd2",
    token: "0x874069fa1eb16d44d622f2e0ca25eea172369bc1",
    amount: "0.1",
  })
  console.log("O.1 CUSD Transfred\n TxHash", tokenTranferHash)
  await waitForInput('Press Enter to continue...');

  // Subscribe the user to overdraft
  console.log("\nSubscribing the user to overdraft...\n")
  const subTxHash = await subscribeToOverdraft({
    account: smartAccount,
    userAddress: smartAccount.account.address,
    initialLimit: "50" //USD
  })
  console.log(`${smartAccount.account.address} subscribed\n TxHash:`, subTxHash)
  await waitForInput('Press Enter to continue...');

  // User overdraft
  console.log("\nUsing an Overdraft...\n")
  const overdraftTxHash = await transferTokenWithOverdraft({
    account: smartAccount,
    from: smartAccount.account.address, 
    to: "0x8E912eE99bfaECAe8364Ba6604612FfDfE46afd2",
    token: "0x874069fa1eb16d44d622f2e0ca25eea172369bc1",
    amount: "1"
  })

  console.log(`1 CUSD Transefered\n TxHash:`, overdraftTxHash)
  let overdraftDebt = await getOverdraftDebt(smartAccount.account.address)
  console.log(`User owes: ${formatUnits(overdraftDebt.amountDue, 18)} KES\n`)

  await waitForInput(`\nSend ${smartAccount.account.address} 0.5 CUSD and Press Enter to continue...`);
  overdraftDebt = await getOverdraftDebt(smartAccount.account.address)
  console.log(`\nUser owes: ${formatUnits(overdraftDebt.amountDue, 18)} KES\n`)

  await waitForInput(`\nSend ${smartAccount.account.address} 10 CKES and Press Enter to continue...`);
  overdraftDebt = await getOverdraftDebt(smartAccount.account.address)
  console.log(`\nUser owes: ${formatUnits(overdraftDebt.amountDue, 18)} KES\n`)

  console.log(`Clixpesa: Making money anc crypto simple for everyone`)
}

main().catch(console.error);