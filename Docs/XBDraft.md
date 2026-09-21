变身机制：

- 变其他鸟
- 次数上限、进入时次数（默认max）、回复道具
- 解锁新鸟的道具（碰一下，动画，解锁）
- **动画：**
    - 四种都有
        - Idle
        - walk
        - jump
            - jump_start
            - jump_end
        - falling
    - 夜鹭
        - gliding
    - 绿头鸭
        - swim-idle
        - swim-walk
        - swim-jump
            - jump_start
            - jump_end
    - 企鹅
        - slide
            - slide_start
            - sliding
            - slide_end

鸟掉到水里会死（除了鸭子）

能力：

- 夜鹭：可以滑翔，撞墙掉落
- 绿头鸭：可以游泳（不需要交互按键）
- 企鹅：滑冰，加速跳跃。（不需要交互按键）
- 啄木鸟：破坏特定方块

特殊tile：

- 可破坏
- 按钮：悬浮在空中，碰到就触发（一次性触发）
- 门
- 弹簧：跳n格高（默认1格）