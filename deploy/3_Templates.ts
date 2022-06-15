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

    const { deploy, get } = deployments;
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
        console.log('initialization failed, it was probably already initialized.')
    }
    
    // const factory = await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
    // const art = await artifacts.readArtifact('AludelFactory')
    // const factory = await ethers.getContractAt(art.abi, '0x4E6A2A5055157CcE166a31595cFC5A1ee01B15F0')

    const deployedFactory = await get('AludelFactory')
    const factory = await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)

    console.log('Adding templates to', factory.address)

    // add templates in factory
    if (!(await factory.isInstance(aludel.address))) {
        console.log("adding template")
        await factory.addTemplate(aludel.address, "AludelV2", false)
    } else {
        console.log('Skipping', aludel.address)
    }

};
