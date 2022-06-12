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
        contract: 'src/contracts/AludelFactory.sol:AludelFactory',
        deterministicDeployment: false,
    });

    const result = await deploy('Aludel', {
        from: deployer,
        args: [],
        log: true,
        contract: 'src/contracts/aludel/Aludel.sol:Aludel',
        deterministicDeployment: false
    });

    const aludel = await ethers.getContractAt(
        result.abi,
        result.address
    )

    // instead of using a try catch block this should
    // access the template's contract storage and read the _initialized flag 
    try {
        await aludel.initializeLock();
    } catch (err) {
        console.log('initialization failed, it was probably already initialized.')
    }
    
    const factory = await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
    
    console.log('Adding templates to', factory.address)
    // add templates in factory
    if (!(await factory.isInstance(aludel.address))) {
        console.log("adding template")
        await factory.addTemplate(aludel.address)
    } else {
        console.log('Skipping', aludel.address)
    }

};
