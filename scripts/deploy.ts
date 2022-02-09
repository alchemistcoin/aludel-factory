import { ethers, run } from "hardhat";

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

async function main() {

  const signer = (await ethers.getSigners())[0]
  console.log('Signer:', signer.address)

  // We get the contract to deploy
  const AludelFactory = await ethers.getContractFactory("AludelFactory");
  const factory = await AludelFactory.deploy();
  await factory.deployed()
  console.log("AludelFactory deployed to:", factory.address);
  
  // await factory.deployTransaction.wait(1)
  await sleep(150000)  
  // verify source
  console.log('Verifying source on etherscan')
  await run('verify:verify', {
    address: factory.address,
    constructorArguments: [],
  })

  const AludelTemplate = await ethers.getContractFactory("Aludel");
  const template = await AludelTemplate.deploy();
  await template.deployed()
  console.log("AludelTemplate deployed to:", template.address);
  
  // await template.deployTransaction.wait(1)
  await sleep(150000)  
  
  // verify source
  console.log('Verifying source on etherscan')
  await run('verify:verify', {
    address: template.address,
    constructorArguments: [],
  })

  // add template
  await factory.addTemplate(template.address)

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
