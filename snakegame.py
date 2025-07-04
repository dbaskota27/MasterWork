import curses
from random import randint
import time

# Initialize curses
stdscr = curses.initscr()
curses.curs_set(0)  # Hide cursor
sh, sw = stdscr.getmaxyx()  # Get screen height and width
w = curses.newwin(sh, sw, 0, 0)  # Create new window
w.keypad(1)  # Enable keypad mode
w.timeout(100)  # Refresh every 100ms

# Initial snake position and direction
snake_x = sw // 4
snake_y = sh // 2
snake = [[snake_y, snake_x], [snake_y, snake_x - 1], [snake_y, snake_x - 2]]
direction = curses.KEY_RIGHT

# Place food
food = [sh // 2, sw // 2]
w.addch(food[0], food[1], '*')

score = 0
while True:
    next_key = w.getch()
    direction = direction if next_key == -1 else next_key

    # Calculate new head position
    new_head = [snake[0][0], snake[0][1]]
    if direction == curses.KEY_UP:
        new_head[0] -= 1
    elif direction == curses.KEY_DOWN:
        new_head[0] += 1
    elif direction == curses.KEY_LEFT:
        new_head[1] -= 1
    elif direction == curses.KEY_RIGHT:
        new_head[1] += 1

    # Insert new head
    snake.insert(0, new_head)

    # Check for food collision
    if snake[0] == food:
        score += 1
        food = None
        while food is None:
            nf = [randint(1, sh - 2), randint(1, sw - 2)]
            food = nf if nf not in snake else None
        w.addch(food[0], food[1], '*')
    else:
        tail = snake.pop()
        w.addch(tail[0], tail[1], ' ')

    # Check for game over
    if (snake[0][0] in [0, sh - 1] or
        snake[0][1] in [0, sw - 1] or
        snake[0] in snake[1:]):
        curses.endwin()
        print(f"Game Over! Score: {score}")
        break

    # Draw snake
    w.addch(snake[0][0], snake[0][1], '#')

# Restore terminal settings
curses.endwin()
