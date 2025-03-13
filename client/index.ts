import {account, clixpesaAccount, accountClient, publicClient, pimlicoClient} from "./src/config"

console.log("Account Address:", clixpesaAccount.address);

//1st Tx
const txHash = await accountClient.sendTransaction({
  to: "0x3d2912C44edB46631F48ea227EA1f261ca24B790",
  value: 0n,
  data: "0x",
});

console.log(txHash);