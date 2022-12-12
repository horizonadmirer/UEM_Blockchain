pragma solidity ^0.8.0;

// SPDX-License-Identifier: UNLICENSED

/*
 * CONTRATO INTELIGENTE "SimpleLottery"
 * Se puede compilar con una versión igual o superior a 0.8.0.
 *
 * Su finalidad es permitir a los usuarios apostar entre 
 * dos bandos; en este caso, "true" o "false" y a partir
 * del resultado generado "aleatoriamente", repartir o no las ganancias.
 * La comisión de la casa es de un 1 % por apuesta.
 * Esta comisión no podrá ser alterada en este contrato, pero 
 * se podría hacer un nuevo contrato con una variable "feeRate"
 * específica y que ésta se utilizara en el cálculo de la comisión.
 *
 * Diseñado y desarrollado por @mabamo1 (alias).
 * Nota: este contrato se ha hecho con fines educativos y puede no estar
 * libre de errores de código que pueden poner en peligro los fondos del usuario. 
 */

contract SimpleLottery {

    /* Declaración de variables de estado. */
    // Almacenamiento key=value de todos los jugadores y sus balances.
    mapping(address => uint256) public playersBalance;
    // Dirección pública del dueño del contrato.
    address payable public lotteryOwner;
    // Dirección pública dónde se enviarán las comisiones de las apuestas.
    address payable public houseEdgeAddress;
    // Almacenamiento del balance actual de las comisiones generadas.
    uint256 public houseEdgeBalance;
    // Almacenamiento de un número que será utilizado para propósitos de aleatorización.
    uint256 private randomizerNumber;
    // Almacenamiento de un booleano que será utilizado para pausar o no el contrato.
    // Es decir, permitir o no el juego en caso de emergencias.
    bool public lotteryIsWorking;

    /* Declaración de eventos. Los más relevantes que serán necesarios para el correcto funcionamiento de una dAPP. */
    event NewDeposit(address player, uint256 amount);
    event NewWithdrawal(address player, uint256 amount);
    event NewBet(address player, uint256 betAmount, uint256 feePaid, bool playerChoice, bool isWinner);

    /* Declaración de modificadores. */
    // Modificador para otorgar poder únicamente al dueño del contrato para realizar acciones que sólo este actor debería hacer.
    modifier onlyLotteryOwner() {
        require(msg.sender == lotteryOwner,
            "Solo el propietario de este contrato puede realizar esta accion");
        _;
    }
    // Modificador para comprobar que el contrato inteligente no está pausado y determinadas funciones se deben ejecutar o no.
    modifier isWorking() {
        require(lotteryIsWorking,
            "ADVERTENCIA: El contrato de la loteria esta temporamente pausado");
        _;
    }

    /* Declaración del constructor. */
    constructor(address payable _owner, address payable _houseEdgeAddr) {
        lotteryOwner = _owner;
        houseEdgeAddress = _houseEdgeAddr;
        lotteryIsWorking = true;
    }
    
    /* Declaración de las funciones. */

    // Función setNewOwner() para cambiar el dueño actual del contrato a uno nuevo. 
    // Tiene el modificador onlyLotteryOwner(), lo que hace que sólo el dueño actual puede hacerlo.
    function setNewOwner(address payable _newOwner) onlyLotteryOwner() public {
        lotteryOwner = _newOwner;
    }

    // Función setNewHouseEdgeAddress() para cambiar la dirección actual dónde se reciben las comisiones. 
    // Tiene el modificador onlyLotteryOwner(), lo que hace que sólo el dueño actual puede hacerlo.
    function setNewHouseEdgeAddress(address payable _newHouseEdgeAddr) onlyLotteryOwner() public {
        houseEdgeAddress = _newHouseEdgeAddr;
    }

    // Función setContractStatus() para cambiar el estado del contrato (pausarlo o activarlo). 
    // Tiene el modificador onlyLotteryOwner(), lo que hace que sólo el dueño actual puede hacerlo.
    function setContractStatus(bool _isWorking) onlyLotteryOwner() public {
        lotteryIsWorking = _isWorking;
    }

    // Función withdrawEverything() para enviar todo el balance del contrato a una dirección determinada.
    // En los argumentos también hay que indicar si el contrato continua activo o se pausa. 
    // Tiene el modificador onlyLotteryOwner(), lo que hace que sólo el dueño actual puede hacerlo.
    function withdrawEverything(bool _isWorking, address payable _destinationAddress) onlyLotteryOwner() public {
        setContractStatus(_isWorking);
        _destinationAddress.transfer(address(this).balance);
    }

    // Función checkPlayerBalance() que permite consultar el balance actual de un jugador.
    function checkPlayerBalance(address _player) public view returns(uint256) {
        return(playersBalance[_player]);
    }

    // Función depositEther() para depositar Ether en el contrato. 
    // Tiene el modificador isWorking(), lo que hace que solo se pueda ejecutar 
    // en caso que el contrato esté activo y funcional.
    // Al fin de su ejecución, emite un evento con la información del déposito.
    function depositEther() isWorking() payable public {
        require(msg.value > 0 wei);
        uint256 oldPlayerBalance = checkPlayerBalance(msg.sender);
        playersBalance[msg.sender] += msg.value;
        require(playersBalance[msg.sender] > oldPlayerBalance);
        
        emit NewDeposit(msg.sender, msg.value);
    }

    // Función withdrawEther() para retirar Ether del contrato. 
    // Tiene el modificador isWorking(), lo que hace que solo se pueda ejecutar 
    // en caso que el contrato esté activo y funcional.
    // Se hacen las comprobaciones pertinentes para que el usuario no pueda sacar
    // más fondos de los que tiene disponibles.
    // Al fin de su ejecución, emite un evento con la información del retiro.
    function withdrawEther(uint256 _weiToWithdraw) isWorking() payable public {
        require(playersBalance[msg.sender] > 0 wei 
            && playersBalance[msg.sender] >= _weiToWithdraw, 
            "No tienes suficiente balance para realizar un retiro");
        require(address(this).balance >= _weiToWithdraw,
            "No hay suficiente dinero en el contrato, espera un rato");
        playersBalance[msg.sender] -= _weiToWithdraw;
        payable(msg.sender).transfer(_weiToWithdraw);

        emit NewWithdrawal(msg.sender, _weiToWithdraw);
    }

    // Función randomizeNumber() para generar un número "aleatorio" entre 0 y 9.
    // Esta función será llamada por la función play() para escoger un número ganador.
    // El código de esta función ha sido extraído de:
    // https://blog.finxter.com/how-to-generate-random-numbers-in-solidity/
    // y posteriormente modificado para encajarlo mejor en la idea del contrato.
    // NOTA: La aleatorización en solidity es un tema complejo que puede ser alterado 
    // por actores externos. Muy probablemente haya mejores formas de hacerlo.
    function randomizeNumber() private returns(uint256) {
        return uint256(keccak256(abi.encodePacked(randomizerNumber++))) % 10;
    }

    // Función play() para escoger una opción, realizar una apuesta y jugar. 
    // En los argumentos se debe introducir la opción del jugador "true" o "false" y la cuantía de la apuesta.
    // Tiene el modificador isWorking(), lo que hace que solo se pueda ejecutar 
    // en caso que el contrato esté activo y funcional.
    // Al fin de su ejecución, emite un evento con la información de la apuesta.
    function play(bool _playerChoice, uint256 _betAmount) isWorking() public {
        require(_betAmount <= checkPlayerBalance(msg.sender), 
            "No tienes suficiente balance para realizar la apuesta");
        require(_betAmount > 0,
            "No puedes hacer una apuesta sin valor");
        // Variables de memoria para almacenar el número ganador, 
        // la posible recompensa, la comisión de la apuesta y si finalmente ha ganado o ha perdido.
        uint256 randomNumber = randomizeNumber();
        uint256 possibleReward = (_betAmount * 99) / 100;
        uint256 houseEdgeFromThisBet = _betAmount - possibleReward;
        bool playerIsWinner = false;

        // En este contrato, se considerará que la opción del jugador "true" es un número entre 0 y 4.
        // Y que la opción del jugador "false" es un número entre 5 y 9.
        if(_playerChoice) {
            if(randomNumber < 5) {
                // El jugador ha ganado su apuesta.
                playersBalance[msg.sender] += possibleReward;
                playerIsWinner = true;
            } else {
                // El jugador ha perdido su apuesta.
                playersBalance[msg.sender] -= _betAmount;
            }
        } else {
            if(randomNumber >= 5) {
                // El jugador ha ganado su apuesta.
                playersBalance[msg.sender] += possibleReward;
                playerIsWinner = true;
            } else {
                // El jugador ha perdido su apuesta.
                playersBalance[msg.sender] -= _betAmount;
            }
        }
        // Se actualiza el balance de las comisiones obtenidas y finalmente se llama a la
        // función sendFeesToHouseEdgeAddr() para enviarlas directamente a la dirección establecida.
        houseEdgeBalance += houseEdgeFromThisBet;
        sendFeesToHouseEdgeAddr();

        emit NewBet(msg.sender, _betAmount, houseEdgeFromThisBet, _playerChoice, playerIsWinner);
    }
    // Función sendFeesToHouseEdgeAddr() para enviar las comisiones generadas de las apuestas a la
    // dirección establecida dónde se deben recibir éstas.  
    // Al ser tipo "payable", puede ser llamada por cualquiera, pero será especialmente llamada 
    // tras cada apuesta realizada a través de la función play().
    function sendFeesToHouseEdgeAddr() payable public {
        require(houseEdgeBalance > 0 && houseEdgeBalance <= address(this).balance);
        houseEdgeAddress.transfer(houseEdgeBalance);
        houseEdgeBalance = 0;
    }
}