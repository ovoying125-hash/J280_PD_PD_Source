"""倒立摆只读监测界面，演示模式不打开串口。"""
from collections import deque
import argparse
import math
import queue
import threading
import time
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk

from monitor_protocol import FrameDecoder, decode_monitor
from monitor_protocol import sensor_voltage

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = list_ports = None

BG='#07111f'
CARD='#0e1c2d'
TEXT='#eef5fc'
MUTED='#8b9eb4'
GRID='#203146'
CYAN='#53d5f2'
AMBER='#ffbc61'
PURPLE='#b39bff'
MINT='#66dfb3'


# 单路波形及大数字读数，支持目标参考线和全屏显示。
class WaveCard:
    # 初始化显示组件与内部状态，不自动连接串口。
    def __init__(self,parent,title,color,unit,angle=False,fixed=None):
        self.color,self.unit,self.fixed=color,unit,fixed
        self.title=title
        self.frame=tk.Frame(parent,bg=CARD,highlightbackground=GRID,highlightthickness=1)
        heading=tk.Frame(self.frame,bg=CARD);heading.pack(fill='x',padx=22,pady=(14,0))
        self.title_label=tk.Label(heading,text=title,bg=CARD,fg=MUTED,font=('Microsoft YaHei UI',15))
        self.title_label.pack(side='left')
        self.expand_button=tk.Button(heading,text='全屏',bg=CARD,fg=MUTED,activebackground=GRID,activeforeground=TEXT,
                                     relief='flat',cursor='hand2',font=('Microsoft YaHei UI',11),padx=9,pady=2)
        self.expand_button.pack(side='right')
        row=tk.Frame(self.frame,bg=CARD);row.pack(fill='x',padx=22,pady=(0,2));self.readout_row=row
        self.expanded=False;self.readout_size=None
        self.measure_font=tkfont.Font(root=self.frame,family='Segoe UI',size=88,weight='bold')
        self.actual_group=tk.Frame(row,bg=CARD);self.actual_group.pack(side='left',anchor='s')
        self.actual_caption=tk.Label(self.actual_group,text='实测',bg=CARD,fg=MUTED,font=('Microsoft YaHei UI',16)) if angle else None
        self.actual_line=tk.Frame(self.actual_group,bg=CARD);self.actual_line.pack(anchor='w')
        self.value=tk.StringVar(value='—')
        self.value_label=tk.Label(self.actual_line,textvariable=self.value,bg=CARD,fg=color,font=('Segoe UI',35,'bold'));self.value_label.pack(side='left',anchor='s')
        self.unit_label=tk.Label(self.actual_line,text=unit,bg=CARD,fg=MUTED,font=('Segoe UI',16));self.unit_label.pack(side='left',padx=10,anchor='s',pady=10)
        self.target=None
        self.target_group=None
        self.reference_label=None
        if angle:
            right=tk.Frame(row,bg=CARD);right.pack(side='right',anchor='s',pady=5);self.target_group=right
            self.target_caption=tk.Label(right,text='目标',bg=CARD,fg=AMBER,font=('Microsoft YaHei UI',12));self.target_caption.pack(anchor='e')
            self.reference_label='目标'
            self.target=tk.StringVar(value='—°')
            self.target_label=tk.Label(right,textvariable=self.target,bg=CARD,fg=TEXT,font=('Segoe UI',26,'bold'));self.target_label.pack(anchor='e')
        self.canvas=tk.Canvas(self.frame,bg=CARD,highlightthickness=0,height=205)
        self.canvas.pack(fill='both',expand=True,padx=12,pady=(0,12))
        self.frame.bind('<Configure>',lambda _event:self.fit_readouts())
        self.value.trace_add('write',lambda *_args:self.fit_readouts())
        if self.target is not None:self.target.trace_add('write',lambda *_args:self.fit_readouts())

    # 切换单图与四图状态，恢复对应字号和排版。
    def set_expanded(self,expanded):
        self.expanded=expanded;self.readout_size=None
        self.readout_row.pack_configure(padx=32 if expanded else 22,pady=(6,8) if expanded else (0,2))
        if self.actual_caption is not None:
            if expanded:self.actual_caption.pack(before=self.actual_line,anchor='w')
            else:self.actual_caption.pack_forget()
        if self.target_group is not None:
            self.target_group.pack_forget()
            self.target_group.pack(side='left' if expanded else 'right',anchor='s',
                                   padx=(32,0) if expanded else 0,pady=0 if expanded else 5)
            self.target_caption.configure(font=('Microsoft YaHei UI',16 if expanded else 12))
            self.target_caption.pack_configure(anchor='w' if expanded else 'e')
            self.target_label.pack_configure(anchor='w' if expanded else 'e')
        if expanded:self.fit_readouts()
        else:
            self.value_label.configure(font=('Segoe UI',35,'bold'))
            self.unit_label.configure(font=('Segoe UI',16),fg=MUTED)
            self.unit_label.pack_configure(padx=10,pady=10)
            if self.target is not None:self.target_label.configure(font=('Segoe UI',26,'bold'))

    # 依据窗口宽度适配大数字字号，角度单位与读数对齐。
    def fit_readouts(self):
        if not self.expanded:return
        width=self.readout_row.winfo_width()
        if width<200:width=self.frame.winfo_width()-64
        needed=self.measure_font.measure(self.value.get())+self.measure_font.measure(self.unit)*(1 if self.unit=='°' else .42)
        if self.target is not None:needed+=self.measure_font.measure(self.target.get())
        size=max(30,min(88,int(88*max(1,width-80)/max(1,needed))))
        if size==self.readout_size:return
        self.readout_size=size
        self.value_label.configure(font=('Segoe UI',size,'bold'))
        self.unit_label.configure(font=('Segoe UI',size,'bold') if self.unit=='°' else ('Segoe UI',max(20,round(size*.4))),fg=self.color if self.unit=='°' else MUTED)
        if self.unit=='°':self.unit_label.pack_configure(padx=0,pady=0)
        if self.target is not None:self.target_label.configure(font=('Segoe UI',size,'bold'))

    # 绘制最近十秒曲线及目标或往复基准虚线。
    def draw(self,samples,now,reference=None,span=10):
        c=self.canvas;w,h=c.winfo_width(),c.winfo_height()
        if w<150 or h<65:return
        c.delete('all');left,right,top,bottom=57,w-12,28,h-25
        start=now-span
        if self.reference_label is not None:
            c.create_text(right,1,text='┄ '+self.reference_label,anchor='ne',fill=AMBER,font=('Microsoft YaHei UI',10))
        data=[(t,v) for t,v in samples if start<=t<=now]
        targets=[(t,v) for t,v in (reference or []) if start<=t<=now]
        if self.fixed:low,high=self.fixed
        else:
            values=[v for _,v in data]+[v for _,v in targets]
            low,high=(min(values+[0]),max(values+[0])) if values else (-1,1)
            pad=max((high-low)*.15,1);low-=pad;high+=pad
        # 将采样时刻映射到横轴像素位置。
        def xx(t):return left+(t-start)*(right-left)/span
        # 将通道数值映射到纵轴像素位置。
        def yy(v):return bottom-(v-low)*(bottom-top)/(high-low)
        for i in range(5):
            y=top+(bottom-top)*i/4;x=left+(right-left)*i/4
            c.create_line(left,y,right,y,fill=GRID)
            c.create_line(x,top,x,bottom,fill=GRID)
            c.create_text(left-9,y,text=f'{high-(high-low)*i/4:.1f}',anchor='e',fill=MUTED,font=('Segoe UI',10))
            c.create_text(x,bottom+17,text=f'{-span+span*i/4:g}s',fill=MUTED,font=('Segoe UI',10))
        if len(data)>1:
                                                                           
            buckets={}
            for t,v in data:
                x=round(xx(t));bucket=buckets.setdefault(x,[v,v,v]);bucket[0]=min(bucket[0],v);bucket[1]=max(bucket[1],v);bucket[2]=v
            points=[]
            for x,(lo,hi,last) in sorted(buckets.items()):
                if lo!=hi:c.create_line(x,yy(lo),x,yy(hi),fill=self.color)
                points.extend((x,yy(last)))
            if len(points)>=4:c.create_line(*points,fill=self.color,width=2,tags='actual_trace')
        if targets:
            points=[];previous=None
            for t,v in targets:
                if previous is None:points.extend((xx(t),yy(v)))
                elif v!=previous:points.extend((xx(t),yy(previous),xx(t),yy(v)))
                previous=v
            points.extend((right,yy(previous)))
            if len(points)>=4:c.create_line(*points,fill=AMBER,width=2,dash=(8,5),tags='user_target')
        if not data:c.create_text((left+right)/2,(top+bottom)/2,text='等待数据',fill=MUTED,font=('Microsoft YaHei UI',16))


# 主窗口协调串口线程、数据缓冲、四图布局与独立全屏。
class MonitorWindow:
    # 初始化显示组件与内部状态，不自动连接串口。
    def __init__(self,root,demo=False):
        self.root,self.demo=root,demo
        root.title('J280 · 实时监测');root.geometry('1440x940');root.minsize(1100,760);root.configure(bg=BG)
        self.events=queue.Queue();self.stop_event=threading.Event();self.worker=None;self.session=0
        self.single_key=None
        self.saved_window=None
        self.connected=False;self.last_sample=None;self.started=time.monotonic();self.latest=None
        self.full_scale=3.3
        self.samples={name:deque(maxlen=4000) for name in ('voltage','angle','speed','pwm','target','reference')}
        self.status=tk.StringVar(value='演示 · 模拟数据' if demo else '未连接')
        style=ttk.Style(root);style.theme_use('clam')
        style.configure('Monitor.TCombobox',fieldbackground=CARD,background=CARD,foreground=TEXT,
                        arrowcolor=CYAN,bordercolor=GRID,lightcolor=GRID,darkcolor=GRID,padding=6)
        style.map('Monitor.TCombobox',fieldbackground=[('readonly',CARD)],foreground=[('readonly',TEXT)])
        header=tk.Frame(root,bg=BG);header.pack(fill='x',padx=26,pady=(22,16));self.header=header
        tk.Label(header,text='J280',fg=TEXT,bg=BG,font=('Segoe UI',27,'bold')).pack(side='left')
        tk.Label(header,text='实时监测',fg=MUTED,bg=BG,font=('Microsoft YaHei UI',15)).pack(side='left',padx=20)
        self.port=tk.StringVar();self.baud=tk.StringVar(value='115200')
        self.button=tk.Button(header,text='连接',command=self.toggle,bg=CYAN,fg=BG,activebackground='#8ae8fa',relief='flat',font=('Microsoft YaHei UI',12,'bold'),padx=22,pady=6)
        self.button.pack(side='right',padx=(12,0))
        self.baud_box=ttk.Combobox(header,textvariable=self.baud,values=('115200',),width=9,font=('Segoe UI',13),state='readonly',style='Monitor.TCombobox');self.baud_box.pack(side='right',padx=8)
        self.port_box=ttk.Combobox(header,textvariable=self.port,width=12,font=('Segoe UI',13),postcommand=self.refresh_ports,style='Monitor.TCombobox');self.port_box.pack(side='right')
        self.refresh_ports()
        body=tk.Frame(root,bg=BG);body.pack(fill='both',expand=True,padx=26);self.body=body
        for i in range(2):body.columnconfigure(i,weight=1,uniform='cards');body.rowconfigure(i,weight=1,uniform='rows')
        self.cards={
            'speed':WaveCard(body,'转臂速度',PURPLE,'°/s'),
            'pwm':WaveCard(body,'PWM',MINT,'%',fixed=(-100,100)),
            'voltage':WaveCard(body,'摆杆电压 ≈',CYAN,'V',fixed=(0,self.full_scale)),
            'angle':WaveCard(body,'转臂 · 实际角度',AMBER,'°',angle=True)}
        for key,card in self.cards.items():
            card.expand_button.configure(command=lambda name=key:self.toggle_single(name))
            card.canvas.bind('<Double-Button-1>',lambda _event,name=key:self.toggle_single(name))
        self.layout_cards()
        footer=tk.Frame(root,bg=BG);footer.pack(side='bottom',before=body,fill='x',padx=28,pady=13);self.footer=footer
        tk.Label(footer,textvariable=self.status,bg=BG,fg=MUTED,font=('Microsoft YaHei UI',11)).pack(side='left')
        tk.Label(footer,text='10 s',bg=BG,fg=MUTED,font=('Segoe UI',11)).pack(side='right')
        if demo:self.button.configure(state='disabled');self.port_box.configure(state='disabled');self.baud_box.configure(state='disabled')
        root.protocol('WM_DELETE_WINDOW',self.close)
        root.bind('<Escape>',self.exit_single)
        root.after(40,self.poll)

    # 恢复上排速度和占空比、下排电压和角度的四图布局。
    def layout_cards(self):
        for i,card in enumerate(self.cards.values()):
            card.frame.grid(row=i//2,column=i%2,rowspan=1,columnspan=1,sticky='nsew',
                            padx=(0,8) if i%2==0 else (8,0),pady=(0,8) if i<2 else (8,0))
            card.expand_button.configure(text='全屏')
            card.title_label.configure(text=card.title)
            card.set_expanded(False)

    # 只改变显示布局，数据采集继续保留所有通道。
    def toggle_single(self,key):
        if self.single_key==key:
            self.exit_single();return
        if key not in self.cards:return
        if self.single_key is None:
            self.saved_window=(self.root.state(),self.root.geometry(),self.root.attributes('-fullscreen'))
        self.single_key=key
        self.header.pack_forget();self.footer.pack_forget()
        self.body.pack_configure(padx=0,pady=0)
        for card in self.cards.values():card.frame.grid_remove();card.set_expanded(False)
        card=self.cards[key]
        card.frame.grid(row=0,column=0,rowspan=2,columnspan=2,sticky='nsew',padx=0,pady=0)
        card.expand_button.configure(text='返回四图（Esc）')
        card.title_label.configure(text=card.title+(' · 演示' if self.demo else ''))
        card.set_expanded(True)
        self.root.attributes('-fullscreen',True)
        self.root.focus_set()

    # 退出全屏并恢复进入前的窗口状态。
    def exit_single(self,event=None):
        if self.single_key is None:return 'break'
        self.single_key=None
        self.layout_cards()
        self.body.pack_configure(padx=26,pady=0)
        self.header.pack(before=self.body,fill='x',padx=26,pady=(22,16))
        self.footer.pack(side='bottom',before=self.body,fill='x',padx=28,pady=13)
        state,geometry,fullscreen=self.saved_window
        self.root.attributes('-fullscreen',fullscreen)
        if state=='normal':self.root.geometry(geometry)
        self.root.state(state)
        return 'break'

    # 刷新可选串口，不主动打开设备。
    def refresh_ports(self):
        ports=[p.device for p in list_ports.comports()] if list_ports else []
        self.port_box.configure(values=ports)
        if ports and not self.port.get():self.port.set(ports[0])

    # 由用户点击连接或断开，串口线程仅执行接收。
    def toggle(self):
        if self.demo:return
        if self.worker and self.worker.is_alive():
            self.stop_event.set();self.button.configure(state='disabled');self.status.set('正在断开');return
        if serial is None:self.status.set('缺少 pyserial');return
        name=self.port.get().strip()
        if not name:self.status.set('选择串口');return
        self.session+=1;session=self.session;self.stop_event=threading.Event();self.connected=False
        for values in self.samples.values():values.clear()
        self.last_sample=self.latest=None
        self.reset_values();self.status.set('正在连接');self.button.configure(text='断开')
        self.worker=threading.Thread(target=self.serial_worker,args=(session,name,int(self.baud.get()),self.stop_event),daemon=True);self.worker.start()

    # 后台接收串口帧，禁止向设备发送任何字节。
    def serial_worker(self,session,name,baud,stop):
                                                                                       
        try:
            with serial.Serial(name,baud,timeout=.05,write_timeout=.3) as port:
                self.events.put((session,'connected',name))
                decoder=FrameDecoder()
                while not stop.is_set():
                    chunk=port.read(min(max(port.in_waiting,1),4096))
                    timestamp=time.monotonic()
                    for kind,payload in decoder.feed(chunk):
                        if kind==0x39:
                            try:self.events.put((session,'sample',(timestamp,decode_monitor(payload))))
                            except ValueError:pass
        except Exception as exc:self.events.put((session,'error',str(exc)))
        finally:self.events.put((session,'closed',None))

    # 换算电压、角度、速度和占空比，往复时以基准为虚线。
    def accept(self,timestamp,reading):
        self.last_sample=timestamp;self.latest=reading
        data={'voltage':sensor_voltage(reading['adc_code'],self.full_scale), 'angle':reading['actual_degrees'],
              'speed':reading['speed_degrees_s'],'pwm':reading['pwm_per_mille']/10,'target':reading['user_degrees']}
        reciprocal=reading.get('reciprocal_enabled',False)
        data['reference']=reading['reciprocal_center_degrees'] if reciprocal else data['target']
        self.cards['angle'].reference_label=f"往复基准 {data['reference']:+.2f}°" if reciprocal else '目标'
        for key,value in data.items():self.samples[key].append((timestamp,value))
        for key,card in self.cards.items():card.value.set(f'{data[key]:.3f}' if key=='voltage' else f'{data[key]:+.2f}')
        self.cards['angle'].target.set(f"{data['target']:+.2f}°")

    # 清空失效的实时数字，避免断线后继续显示旧值。
    def reset_values(self):
        for card in self.cards.values():card.value.set('—')
        self.cards['angle'].target.set('—°')

    # 从消息队列更新界面，演示数据仅在显式演示模式生成。
    def poll(self):
        now=time.monotonic()
        if self.demo:
            t=now-self.started;target=60 if int(t/6)%2==0 else -60
            actual=target*(1-math.exp(-(t%6)*1.7))+2*math.sin(t*4)*math.exp(-(t%6))
            speed=(actual-self.latest['actual_degrees'])/.04 if self.latest else 0
            self.accept(now,{'adc_code':1241+round(9*math.sin(t*3)), 'actual_degrees':actual,'user_degrees':target,
                             'speed_degrees_s':speed,'pwm_per_mille':round(100*math.sin(t*5)+20*math.sin(t*43))})
        while True:
            try:session,kind,value=self.events.get_nowait()
            except queue.Empty:break
            if session!=self.session:continue
            if kind=='connected':self.connected=True;self.status.set(f'{value} · 等待数据')
            elif kind=='sample':self.accept(*value)
            elif kind=='error':self.status.set(f'连接失败：{value}');self.connected=False
            elif kind=='closed':
                self.connected=False;self.button.configure(text='连接',state='normal')
                if self.stop_event.is_set():self.status.set('已断开')
                self.reset_values()
        if not self.demo and self.connected:
            if self.last_sample is None:self.status.set(f'{self.port.get()} · 等待新版固件数据')
            elif now-self.last_sample>2:self.status.set('数据中断');self.reset_values()
            else:
                state_name=('停止','起摆','直立平衡','故障')[self.latest.get('state',0)]
                reason=self.latest.get('fault_reason',0)
                detail=f' · 故障代码 {reason}' if reason else ''
                self.status.set(f'{self.port.get()} · {state_name}{detail}')
        visible=self.cards.items() if self.single_key is None else ((self.single_key,self.cards[self.single_key]),)
        for key,card in visible:card.draw(self.samples[key],now,self.samples['reference'] if key=='angle' else None)
        self.root.after(40,self.poll)

    # 通知接收线程退出并关闭窗口。
    def close(self):
        self.stop_event.set()
        self.root.destroy()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--demo',action='store_true')
    args=parser.parse_args();root=tk.Tk();MonitorWindow(root,demo=args.demo);root.mainloop()
