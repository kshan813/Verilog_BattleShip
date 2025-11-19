# Verilog_BattleShip

Overview
For our project, we will create the 2-player game, Battleship, on the FPGA board. An analog stick  will be used to place ships and select locations to “fire” at. The display will show the results of the players firing attempt, the rules to the game, and the current board with the score. Buttons will be used to reset and commit to player moves (launch).

Design Description

Player Controls: For the controls, the joystick will select a position on the 9x9 board. The player can place ships using the buttons on the analog, and the ships will be colored grid squares. During the game, the players will both initially take turns placing all their ships. Then for the next rounds they will each be able to select a coordinate to fire at and see a result of their attempt on the seven-segment display as “HIT” or “FAIL”. Their boards will also be updated with game play results.
	
Graphics: The board is a 9x9 board of squares. The color of the square will represent what is there. Green is a ship, red is a hit ship, and white is a missed location. There will be 5 ships of lengths 5, 4, 3, 3 and 2 respectively. There will also be graphics to handle switching players 

Switching Players: In order to ensure that players cannot cheat or peak at each other's boards, between moves the screen will be blank and the player must hit a button on the FPGA to confirm it is their turn and view the screen. 
	
FPGA Components: For the game we will be using the PMOD JSTK (joystick), Seven-Segment Display, and Basys 3 built-in Buttons/Switches.
