#!/bin/bash
###
 # @Author: wangqiji wwwwdqiji@gmail.com
 # @Date: 2025-07-13 14:40:25
 # @LastEditors: wangqiji wwwwdqiji@gmail.com
 # @LastEditTime: 2025-07-14 13:28:37
 # @FilePath: \ccip_rebase_token\bridgeToArbitrum.sh  # 文件名改为 bridgeToArbitrum
### 

# 定义常量 
AMOUNT=100000000000

# ARBITRUM 配置（替换为实际值）
ARBITRUM_CHAIN_SELECTOR="3478487238524512106"  # Arbitrum Sepolia 链选择器
ARBITRUM_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"  # 替换为实际 Arbitrum Router
ARBITRUM_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"  # 替换为实际 Arbitrum LINK

# SEPOLIA 配置（保持不变）
SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM="0x62e731218d0D47305aba2BE3751E7EE9E5520790"
SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
SEPOLIA_RNM_PROXY_ADDRESS="0xba3f6251de62dED61Ff98590cB2fDf6871FbB991"
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
SEPOLIA_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"

export DEPLOYER_PRIVATE_KEY="YOUR PRIVKEY"
# 编译和部署合约（使用标准EVM模式）
source .env

# 编译合约
forge build

# 在 SEPOLIA 上部署代币和资金池
echo "在 Sepolia 上部署代币和资金池..."
sepolia_output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer \
    --rpc-url ${SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    --broadcast)

SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$sepolia_output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL_ADDRESS=$(echo "$sepolia_output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Sepolia rebase token 地址: $SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Sepolia 资金池地址: $SEPOLIA_POOL_ADDRESS"

# 在 SEPOLIA 上部署保险库
echo "在 Sepolia 上部署保险库..."
vault_output=$(forge script ./script/Deployer.s.sol:VaultDeployer \
    --rpc-url ${SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    --broadcast \
    --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS})

VAULT_ADDRESS=$(echo "$vault_output" | grep 'vault: contract Vault' | awk '{print $NF}')
echo "Sepolia 保险库地址: $VAULT_ADDRESS"

# 在 ARBITRUM 上部署代币和资金池
echo "在 Arbitrum 上部署代币和资金池..."
arbitrum_output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer \
    --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    --broadcast \
    --legacy)

ARBITRUM_REBASE_TOKEN_ADDRESS=$(echo "$arbitrum_output" | grep 'token: contract RebaseToken' | awk '{print $4}')
ARBITRUM_POOL_ADDRESS=$(echo "$arbitrum_output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Arbitrum rebase token 地址: $ARBITRUM_REBASE_TOKEN_ADDRESS"
echo "Arbitrum 资金池地址: $ARBITRUM_POOL_ADDRESS"

# 配置 SEPOLIA 资金池指向 ARBITRUM
echo "配置 Sepolia 资金池指向 Arbitrum..."
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript \
    --rpc-url ${SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    --broadcast \
    --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
    ${SEPOLIA_POOL_ADDRESS} \
    ${ARBITRUM_CHAIN_SELECTOR} \
    ${ARBITRUM_POOL_ADDRESS} \
    ${ARBITRUM_REBASE_TOKEN_ADDRESS} \
    false 0 0 false 0 0

# 配置 ARBITRUM 资金池指向 SEPOLIA
echo "配置 Arbitrum 资金池指向 Sepolia..."
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript \
    --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    --broadcast \
    --legacy \
    --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
    ${ARBITRUM_POOL_ADDRESS} \
    ${SEPOLIA_CHAIN_SELECTOR} \
    ${SEPOLIA_POOL_ADDRESS} \
    ${SEPOLIA_REBASE_TOKEN_ADDRESS} \
    false 0 0 false 0 0

# 存款到 SEPOLIA 保险库
echo "向 Sepolia 保险库存款..."
cast send ${VAULT_ADDRESS} \
    --value ${AMOUNT} \
    --rpc-url ${SEPOLIA_RPC_URL} \
    --private-key ${DEPLOYER_PRIVATE_KEY} \
    "deposit()"

# 跨链转账到 ARBITRUM
echo "向 Arbitrum 跨链转账..."
SEPOLIA_BALANCE_BEFORE=$(cast balance $(cast wallet address --private-key ${DEPLOYER_PRIVATE_KEY}) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "跨链前 Sepolia 余额: $SEPOLIA_BALANCE_BEFORE"

clean() {
    echo "$1" | tr -d '\r\n[:space:]'
}

ARBITRUM_CHAIN_SELECTOR=$(clean "$ARBITRUM_CHAIN_SELECTOR")
AMOUNT=$(clean "$AMOUNT")
SEPOLIA_REBASE_TOKEN_ADDRESS=$(clean "$SEPOLIA_REBASE_TOKEN_ADDRESS")
SEPOLIA_LINK_ADDRESS=$(clean "$SEPOLIA_LINK_ADDRESS")
SEPOLIA_ROUTER=$(clean "$SEPOLIA_ROUTER")

forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url ${SEPOLIA_RPC_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --sig "run(uint64,uint256,address,address,address,address)" ${ARBITRUM_CHAIN_SELECTOR} ${AMOUNT} $(cast wallet address --private-key ${DEPLOYER_PRIVATE_KEY}) ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${SEPOLIA_ROUTER} ${SEPOLIA_LINK_ADDRESS}

SEPOLIA_BALANCE_AFTER=$(cast balance $(cast wallet address --private-key ${DEPLOYER_PRIVATE_KEY}) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "跨链后 Sepolia 余额: $SEPOLIA_BALANCE_AFTER"

# 检查 ARBITRUM 余额
echo "检查 Arbitrum 余额..."
ARBITRUM_BALANCE=$(cast balance $(cast wallet address --private-key ${DEPLOYER_PRIVATE_KEY}) --erc20 ${ARBITRUM_REBASE_TOKEN_ADDRESS} --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL})
echo "Arbitrum 上的代币余额: $ARBITRUM_BALANCE"