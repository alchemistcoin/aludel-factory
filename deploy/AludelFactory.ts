import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Contract, ContractFactory } from '@ethersproject/contracts'

export default async function ({
    ethers,
    getNamedAccounts,
    getUnnamedAccounts,
    deployments,
    artifacts
}: HardhatRuntimeEnvironment) {

    async function deployTemplate(
        templateName: string,
        libraries?: {[key: string]: string
    } ): Promise<Contract> {
    // } ): Promise<[DeployResult, Contract]> {
            const result = await deploy(templateName, {
            from: deployer,
            args: [],
            log: true,
            libraries,
            deterministicDeployment: false,
        });
        return ethers.getContractAt(templateName, result.address)
    }

    const { deploy } = deployments;
    const { deployer, dev } = await getNamedAccounts();
    
    console.log(deployer)

    // deploy factory 
    const deployedFactory = await deploy("AludelFactory", {
        from: deployer,
        args: [],
        log: true,
        deterministicDeployment: false,
    });

    // deploy libraries
    const fifoLibrary = await deploy('FIFO', {
        from: deployer,
        log: true,
        deterministicDeployment: false
    })

    // deploy aludel v1.5
    const aludel = await deployTemplate('Aludel')
    await aludel.initializeLock();
    

    // deploy aludel timed lock
    const aludelTimedLock = await deployTemplate('AludelTimedLock', {
        FIFO: fifoLibrary.address
    })
    await aludelTimedLock.initializeLock();

    const factory = await ethers.getContractAt('AludelFactory', deployedFactory.address)
    
    console.log('Adding templates to', factory.address)
    // add templates in factory
    if (!(await factory.isInstance(aludel.address))) {
        await factory.addTemplate(aludel.address)
    } else {
        console.log('Skipping', aludel.address)
    }
    
    if (!(await factory.isInstance(aludelTimedLock.address))) {
        await factory.addTemplate(aludelTimedLock.address)
    } else {
        console.log('Skipping', aludelTimedLock.address)
    }
};
