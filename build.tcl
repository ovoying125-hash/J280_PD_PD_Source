# 创建路径以脚本所在位置为准，适用于包含中文或空格的工程目录。
set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
open_project j280_pd_pd.gprj
set_option -top_module j280_board_top
set_option -include_path {src}
# 第四按键与串行配置接口复用，引脚改为普通输入，专用下载接口保留。
set_option -use_sspi_as_gpio 1
set_option -output_base_name j280_pd_pd
run all
run close
