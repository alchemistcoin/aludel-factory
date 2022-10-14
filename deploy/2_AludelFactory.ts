import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function ({
    ethers,
    getNamedAccounts,
    getUnnamedAccounts,
    deployments,
    artifacts
}: HardhatRuntimeEnvironment) {

    const { deploy } = deployments;
    const { deployer, dev } = await getNamedAccounts();

    const recipient = deployer
    const bps = 100

    // deploy factory 
    const deployedFactory = await deploy("AludelFactory", {
        from: deployer,
        args: [recipient, bps],
        log: true,
        contract: 'AludelFactory',
        deterministicDeployment: false,
    });

};
module.exports.tags = ["AludelFactory"]
