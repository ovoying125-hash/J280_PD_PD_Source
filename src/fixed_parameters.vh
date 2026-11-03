// 固定参数：控制码使用零至一千六百五十的兼容量程，不代表转换器有效位数。
localparam integer COUNTS_PER_REV=1040, ZERO_CODE=1241;
localparam integer CAPTURE_WINDOW=38, FALL_LIMIT=188;
localparam integer BALANCE_TRAVEL=2000, SWING_TRAVEL=2600;
// 内环增益采用八位小数，外环增益采用十六位小数；内环没有积分项。
localparam signed [23:0] INNER_KP=2893, INNER_KD=102963;
localparam signed [23:0] OUTER_KP=6554, OUTER_KD=360448;
localparam integer SMALL_TILT=40, LARGE_TILT=40, PWM_LIMIT=900;
localparam integer BOTTOM_CODE=360, SWING_TARGET=1000, UPPER_CODE=1249;
localparam integer BOTTOM_WINDOW=20, REARM_DISTANCE=100;
localparam integer FIRST_PWM=850, FIRST_MS=200;
localparam integer SECOND_PWM=650, SECOND_MS=150, THIRD_PWM=850, THIRD_MS=150;
// 四十五度单边往复幅度折合一百三十计数；间隔单位为毫秒。
localparam integer RECIP_AMPLITUDE=130, RECIP_INTERVAL=1750;
localparam integer INNER_MS=1, OUTER_MS=10, MONITOR_MS=20;
localparam integer WRAP_SPAN=1650, PWM_DEADZONE=0;
localparam integer ANGLE_DIRECTION=1, ENCODER_DIRECTION=1;
