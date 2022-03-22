import { DeployResult } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

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
    } ): Promise<DeployResult> {
        return deploy(templateName, {
            from: deployer,
            args: [],
            log: true,
            libraries,
            deterministicDeployment: false,
        });
    }

    const { deploy } = deployments;
    const { deployer, dev } = await getNamedAccounts();
    
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
    // deploy aludel timed lock
    const aludelTimedLock = await deployTemplate('AludelTimedLock', {
        FIFO: fifoLibrary.address
    })
    
    const factory = await ethers.getContractAt('AludelFactory', deployedFactory.address)
    
    // add templates in factory
    if (!(await factory.isInstance(aludel.address))) {
        await factory.addTemplate(aludel.address)
    }
    
    if (!(await factory.isInstance(aludelTimedLock.address))) {
        await factory.addTemplate(aludelTimedLock.address)
    }
};
