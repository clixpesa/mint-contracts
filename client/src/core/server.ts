import axios from 'axios';
import { mnemonicToAccount} from "viem/accounts"
import { type Address } from "viem"

const API_BASE_URL = 'http://localhost:3000';

const api = axios.create({
  baseURL: API_BASE_URL,
});

export async function setMnemonic(userId: string, mnemonic: string) {
  const eoaAddress = mnemonicToAccount(mnemonic).address
  await api.post("/users", {id: userId, mnemonic, eoaAddress})
}

export async function setSmartAccount(userId: string, address: Address) {
  const user = await api.get(`/users/?id=${userId}`)
  await api.put(`/users/${userId}`, {...user.data[0], address})
}

export async function getMnemonic(userId: string): Promise<string> {
  const response = await api.get(`/users?id=${userId}`);
  const user = response.data[0];

  if (!user) {
    throw new Error('User not found');
  }

  return user.mnemonic;
}