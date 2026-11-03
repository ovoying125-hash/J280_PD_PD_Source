"""只读遥测协议：按帧头同步、长度检查和异或校验恢复串口快照。"""
import struct


class FrameDecoder:
    # 串口分包与粘包均通过持久缓冲处理，校验失败仅丢弃一个字节重新同步。
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        frames = []
        while len(self.buffer) >= 5:
            index = self.buffer.find(b'\xa5\x5a')
            if index < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer[-1] == 0xa5 else b''
                break
            del self.buffer[:index]
            if len(self.buffer) < 4:
                break
            kind, size = self.buffer[2:4]
            if size > 64:
                del self.buffer[0]
                continue
            if len(self.buffer) < size + 5:
                break
            checksum = 0
            for value in self.buffer[2:size + 5]:
                checksum ^= value
            if checksum:
                del self.buffer[0]
                continue
            frames.append((kind, bytes(self.buffer[4:size + 4])))
            del self.buffer[:size + 5]
        return frames


def decode_monitor(payload):
    # 遥测保留二十九字节布局，中间保留目标字段等于用户目标，不存在隐藏修正量。
    if len(payload) != 29:
        raise ValueError('遥测载荷长度应为二十九字节')
    user, reference, actual, velocity, pwm, adc, flags, fault, cpr, center, board = struct.unpack('<4ihHBBHiB', payload)
    if cpr == 0:
        raise ValueError('每圈计数不能为零')
    return {
        'adc_code': adc,
        'actual_degrees': actual * 360 / cpr,
        'user_degrees': user * 360 / cpr,
        'speed_degrees_s': velocity * 100 * 360 / (256 * cpr),
        'pwm_per_mille': pwm,
        'reciprocal_enabled': bool(board & 2),
        'reciprocal_center_degrees': center * 360 / cpr,
        'state': flags & 3,
        'fault_reason': fault,
    }


def sensor_voltage(code, full_scale=3.3):
    # 显示传感器侧估计电压，不能作为转换器输入端的直接电压测量。
    return code * full_scale / 1650
