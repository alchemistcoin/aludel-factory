import { ethers, run } from "hardhat";

async function main() {

  const signer = (await ethers.getSigners())[0]
  console.log('Signer:', signer.address)

  // We get the contract to deploy
  const AludelFactory = await ethers.getContractFactory("AludelFactory");
  const factory = await AludelFactory.deploy();
  console.log("AludelFactory deployed to:", factory.address);
  
  await factory.deployTransaction.wait(5)
  // verify source
  console.log('Verifying source on etherscan')
  await run('verify:verify', {
    address: factory.address,
    constructorArguments: [],
  })
  
  
  const AludelTemplate = await ethers.getContractFactory("Aludel");
  const template = await AludelTemplate.deploy();
  
  await template.deployTransaction.wait(5)
  // verify source
  console.log('Verifying source on etherscan')
  await run('verify:verify', {
    address: template.address,
    constructorArguments: [],
  })
  console.log("AludelTemplate deployed to:", template.address);

  await factory.addTemplate(template.address)

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
