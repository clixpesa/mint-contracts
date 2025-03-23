import {
    type Account,
    type Address,
    type Assign,
    type Chain,
    type Client,
    type Hex,
    type LocalAccount,
    type OneOf,
    type Transport,
    type WalletClient,
    concat,
    decodeFunctionData,
    encodeFunctionData,
    hashMessage,
    hashTypedData
} from "viem"
import {
    type SmartAccount,
    type SmartAccountImplementation,
    type UserOperation,
    entryPoint07Abi,
    entryPoint07Address,
    getUserOperationHash,
    toSmartAccount
} from "viem/account-abstraction"
import { getChainId, signMessage } from "viem/actions"
import { getAction } from "viem/utils"
import { getAccountNonce } from "../utils/getAccountNonce"
import { getSenderAddress} from "../utils/getSenderAddress"
import { type EthereumProvider, toOwner } from "../utils/toOwner"

/*
 * This converts LocalAccount (EOA) to a SmartAccount.
 * It is used in the context of a user interacting with a smart contract.
 * @notice Impliments only the entrypoint v.0.7 of the SmartAccount.
 * */

//Types
export type ToClixpesaSmartAccountParameters = {
    client: Client
    owner: OneOf<
        | EthereumProvider
        | WalletClient<Transport, Chain | undefined, Account>
        | LocalAccount
    >
    factoryAddress?: Address
    entryPoint?: Address // default is entryPoint07Address
    index?: bigint
    address?: Address
    nonceKey?: bigint
}

export type ClixpesaSmartAccountImplementation = Assign<
    SmartAccountImplementation<
        typeof entryPoint07Abi
    >, {
        sign: NonNullable<SmartAccountImplementation["sign"]>
    }>

export type ToClixpesaSmartAccountReturnType<> = SmartAccount<ClixpesaSmartAccountImplementation>

enum SignatureType {
    EOA = "0x00"
    // CONTRACT = "0x01",
    // CONTRACT_WITH_ADDR = "0x02"
}

const getAccountInitCode = async (
    owner: Address,
    index = BigInt(0)
): Promise<Hex> => {
    if (!owner) throw new Error("Owner account not found")

    return encodeFunctionData({
        abi: [
            {
                inputs: [
                    {
                        internalType: "address",
                        name: "owner",
                        type: "address"
                    },
                    {
                        internalType: "uint256",
                        name: "salt",
                        type: "uint256"
                    }
                ],
                name: "createAccount",
                outputs: [
                    {
                        internalType: "contract LightAccount",
                        name: "ret",
                        type: "address"
                    }
                ],
                stateMutability: "nonpayable",
                type: "function"
            }
        ],
        functionName: "createAccount",
        args: [owner, index]
    })
}

const getFactoryAddress = (factoryAddress?: Address): Address => {
    if (factoryAddress) return factoryAddress
    return "0xf56c3Ccc72540AfE01755479B5407e7Ee51080EF" //Currently only on Alfajoress
}

async function signWith1271WrapperV1(
    signer: LocalAccount,
    chainId: number,
    accountAddress: Address,
    hashedMessage: Hex
): Promise<Hex> {
    return signer.signTypedData({
        domain: {
            chainId: Number(chainId),
            name: "ClixpesaAccount",
            verifyingContract: accountAddress,
            version: "1"
        },
        types: {
            ClixpesaAccountMessage: [{ name: "message", type: "bytes" }]
        },
        message: {
            message: hashedMessage
        },
        primaryType: "ClixpesaAccountMessage"
    })
}


/**
 * @description Creates an Simple Account from a private key.
 *
 * @returns A Private Key Simple Account.
 */
export async function toClixpesaSmartAccount(
    parameters: ToClixpesaSmartAccountParameters
): Promise<ToClixpesaSmartAccountReturnType> {
    const { 
        client,
        owner,
        factoryAddress: _factoryAddress,
        index = BigInt(0),
        address,
        nonceKey 
    } = parameters

    const localOwner = await toOwner({owner})

    const entryPoint = {
        address: parameters.entryPoint ?? entryPoint07Address,
        abi: entryPoint07Abi,
        version: "0.7"
    } as const

    const factoryAddress = getFactoryAddress(_factoryAddress)

    let accountAddress: Address | undefined = address

    let chainId: number 

    const getMemoizedChainId = async () => {
        if (chainId) return chainId
        chainId = client.chain
            ? client.chain.id
            : await getAction(client, getChainId, "getChainId")({})
        return chainId
    }

    const getFactoryArgs = async () => {
        return {
            factory: factoryAddress,
            factoryData: await getAccountInitCode(localOwner.address, index)
        }
    }

    return toSmartAccount({
        client,
        entryPoint,
        getFactoryArgs,

        async getAddress(): Promise<Address> { 
            if (accountAddress) return accountAddress

            const { factory, factoryData } = await getFactoryArgs()

            accountAddress = await getSenderAddress(client, {
                factory,
                factoryData,
                entryPointAddress: entryPoint.address
            })

            return accountAddress
        },
        async encodeCalls(calls) {
            if (calls.length > 1) {
                return encodeFunctionData({
                    abi: [
                        {
                            inputs: [
                                {
                                    internalType: "address[]",
                                    name: "dest",
                                    type: "address[]"
                                },
                                {
                                    internalType: "uint256[]",
                                    name: "value",
                                    type: "uint256[]"
                                },
                                {
                                    internalType: "bytes[]",
                                    name: "func",
                                    type: "bytes[]"
                                }
                            ],
                            name: "executeBatch",
                            outputs: [],
                            stateMutability: "nonpayable",
                            type: "function"
                        }
                    ],
                    functionName: "executeBatch",
                    args: [
                        calls.map((a) => a.to),
                        calls.map((a) => a.value ?? 0n),
                        calls.map((a) => a.data ?? "0x")
                    ]
                })
            }

            const call = calls.length === 0 ? undefined : calls[0]

            if (!call) {
                throw new Error("No calls to encode")
            }

            return encodeFunctionData({
                abi: [
                    {
                        inputs: [
                            {
                                internalType: "address",
                                name: "dest",
                                type: "address"
                            },
                            {
                                internalType: "uint256",
                                name: "value",
                                type: "uint256"
                            },
                            {
                                internalType: "bytes",
                                name: "func",
                                type: "bytes"
                            }
                        ],
                        name: "execute",
                        outputs: [],
                        stateMutability: "nonpayable",
                        type: "function"
                    }
                ],
                functionName: "execute",
                args: [call.to, call.value ?? 0n, call.data ?? "0x"]
            })
        },
        async decodeCalls(callData) {
            try {
                const decoded = decodeFunctionData({
                    abi: [
                        {
                            inputs: [
                                {
                                    internalType: "address[]",
                                    name: "dest",
                                    type: "address[]"
                                },
                                {
                                    internalType: "uint256[]",
                                    name: "value",
                                    type: "uint256[]"
                                },
                                {
                                    internalType: "bytes[]",
                                    name: "func",
                                    type: "bytes[]"
                                }
                            ],
                            name: "executeBatch",
                            outputs: [],
                            stateMutability: "nonpayable",
                            type: "function"
                        }
                    ],
                    data: callData
                })

                if (decoded.functionName === "executeBatch") {
                    const calls: {
                        to: Address
                        value: bigint
                        data: Hex
                    }[] = []

                    for (let i = 0; i < decoded.args[0].length; i++) {
                        calls.push({
                            to: decoded.args[0][i],
                            value: decoded.args[1][i],
                            data: decoded.args[2][i]
                        })
                    }

                    return calls
                }

                throw new Error("Invalid function name")
            } catch (_) {
                const decoded = decodeFunctionData({
                    abi: [
                        {
                            inputs: [
                                {
                                    internalType: "address",
                                    name: "dest",
                                    type: "address"
                                },
                                {
                                    internalType: "uint256",
                                    name: "value",
                                    type: "uint256"
                                },
                                {
                                    internalType: "bytes",
                                    name: "func",
                                    type: "bytes"
                                }
                            ],
                            name: "execute",
                            outputs: [],
                            stateMutability: "nonpayable",
                            type: "function"
                        }
                    ],
                    data: callData
                })

                return [
                    {
                        to: decoded.args[0],
                        value: decoded.args[1],
                        data: decoded.args[2]
                    }
                ]
            }
        },
        async getNonce(args) {
            return getAccountNonce(client, {
                address: await this.getAddress(),
                entryPointAddress: entryPoint.address,
                key: nonceKey ?? args?.key
            })
        },
        async getStubSignature() {
            const signature =
                "0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c"
            return concat([SignatureType.EOA, signature])
        },
        async sign({ hash }) {
            return this.signMessage({ message: hash })
        },
        async signMessage ({ message }){
            const signature = await signWith1271WrapperV1(
                localOwner,
                await getMemoizedChainId(),
                await this.getAddress(),
                hashMessage(message)
            )

            return concat([SignatureType.EOA, signature])
        },
        async signTypedData (typedData){
            const signature = await signWith1271WrapperV1(
                localOwner,
                await getMemoizedChainId(),
                await this.getAddress(),
                hashTypedData(typedData)
            )

            return concat([SignatureType.EOA, signature])
        },
        async signUserOperation(parameters) {
            const { chainId = await getMemoizedChainId(), ...userOperation } =
                parameters

            const hash = getUserOperationHash({
                userOperation: {
                    ...userOperation,
                    signature: "0x"
                } as UserOperation<"0.7">,
                entryPointAddress: entryPoint.address,
                entryPointVersion: entryPoint.version,
                chainId: chainId
            })

            const signature = await signMessage(client, {
                account: localOwner,
                message: {
                    raw: hash
                }
            })

            return concat([SignatureType.EOA, signature])
            
        }
        
    }) as Promise<ToClixpesaSmartAccountReturnType>
}
