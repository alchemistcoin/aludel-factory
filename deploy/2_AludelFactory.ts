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

    // deploy factory 
    const deployedFactory = await deploy("AludelFactory", {
        from: deployer,
        args: [],
        log: true,
        contract: 'AludelFactory',
        deterministicDeployment: false,
    });

};
