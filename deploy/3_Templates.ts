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

    const { deploy, get, log } = deployments;
    const { deployer, dev } = await getNamedAccounts();

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
        log('initialization failed, it was probably already initialized.')
    }
    
    const deployedFactory = await get('AludelFactory')
    const factory = await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)

    log('Adding templates to', factory.address)

    // add templates in factory
    if (!(await factory.isAludel(aludel.address))) {
        log("adding template")
        await factory.addTemplate(aludel.address, "AludelV2", false)
    } else {
        log('Skipping', aludel.address)
    }

}

module.exports.tags = ['AludelV1Template']
module.exports.dependencies = ['AludelFactory']
