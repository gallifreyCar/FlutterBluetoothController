import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '天气检测',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ScanBluePage(),
    );
  }
}

class ScanBluePage extends StatefulWidget {
  ScanBluePage({Key? key}) : super(key: key);

  @override
  State<ScanBluePage> createState() => _ScanBluePageState();
}

class _ScanBluePageState extends State<ScanBluePage> {
  /// 初始化变量
  //蓝牙状态：初始未知
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  //蓝牙实例
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  //蓝牙连接实例
  BluetoothConnection? connection = null;

  //蓝牙是否连接的判断
  bool get isConnected => connection != null && connection!.isConnected;

  //蓝牙设备列表
  List<BluetoothDevice> _devicesList = [];

  //选定的蓝牙设备
  BluetoothDevice? _device;

  //是否取消连接
  bool isDisconnecting = false;

  //用于判断是否处于连接状态
  bool _connected = false;

  //按钮是否可以使用（当设备连接时，应该不能按压按钮）
  bool _isButtonUnavailable = false;

  //判断是否在处理
  bool isConvertingData = false;
  //初始数据List
  List<int> initDataList = [
    32,
    49,
    55,
    32,
    32,
    51,
    51,
    32,
    32,
    48,
    32,
    32,
    48,
    32,
    32,
    48,
    32,
    32,
    48,
    32,
    32,
    49,
    56,
    32,
    32,
    50,
    55,
    32,
    32,
    49,
    48,
    48,
    32
  ];

  //翻译出来的ascii字符串
  String dataToString = '';

  //最终处理完数据的列表
  List finalDataList = [];

  //报警判断
  bool warn1 = false;
  bool warn2 = false;
  bool warn3 = false;

  ///初始化页面数据
  // 检测用户是否打开手机蓝牙设置
  // 根据蓝牙状态情况，请求打开手机蓝牙权限
  @override
  void initState() {
    super.initState();
    //获取蓝牙状态
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    //如果蓝牙未开启，然后请求权限，打开蓝牙
    enableBluetooth();

    // 监听蓝牙状态更改
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        //检索匹配的硬件列表
        getPairedDevices();
      });
    });
  }

  ///重写销毁函数,页面关闭时关闭连接并释放资源
  @override
  void dispose() {
    if (isConnected) {
      isDisconnecting = true;
      connection?.dispose();
      connection = null;
    }
    super.dispose();
  }

  ///开启蓝牙
  Future<bool> enableBluetooth() async {
    //获取当前的蓝牙状态
    _bluetoothState = await FlutterBluetoothSerial.instance.state;

    //先判断蓝牙是否开启，未开启先请求开启蓝牙
    //然后检索蓝牙匹配的设备
    if (_bluetoothState == BluetoothState.STATE_OFF) {
      await FlutterBluetoothSerial.instance.requestEnable();
      await getPairedDevices();
      return true;
    } else {
      await getPairedDevices();
    }
    return false;
  }

  ///搜索蓝牙设备
  Future<void> getPairedDevices() async {
    List<BluetoothDevice> devices = [];

    //获取匹配的设备列表
    try {
      devices = await _bluetooth.getBondedDevices();
    } on PlatformException {
      print("Error");
    }
    // 如果数据未加载完，处于未挂载状态(mounted)，返回
    // 如果数据加载成功,处于挂载状态(mounted),setState刷新页面数据
    if (!mounted) {
      return;
    }

    //存储设备列表
    setState(() {
      _devicesList = devices;
    });
  }

  ///发送信息
  void _sendMessage(int num) async {
    connection!.output.add(Uint8List.fromList([num]));
    await connection!.output.allSent;
  }

  ///下拉菜单的菜单项
  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devicesList.isEmpty) {
      items.add(const DropdownMenuItem(
        child: Text('NONE'),
      ));
    } else {
      for (var device in _devicesList) {
        items.add(DropdownMenuItem(
          child: Text(device.name ?? "NONE"),
          value: device,
        ));
      }
    }
    return items;
  }

  ///连接设备  接收数据
  void _connect() async {
    //按钮可以使用
    setState(() {
      _isButtonUnavailable = true;
    });

    if (_device == null) {
      show('没有设备可以连接');
    } else {
      if (!isConnected) {
        await BluetoothConnection.toAddress(_device!.address).then((_connection) {
          show('连接设备成功');
          connection = _connection;
          setState(() {
            _connected = true;
          });

          //用之前定义的isDisconnecting变量进行连接监听
          //当从连接中调用dispose、finish 或 close 方法时会触发 onDone 方法，所有这些都会导致连接断开。
          //接收数据
          connection!.input!.listen((data) {
            //获取数据
            setState(() {
              initDataList = data;
            });

            //如果没有在处理数据，才可以处理数据
            if (!isConvertingData) {
              convertData();
            }
          }).onDone(() {
            if (isDisconnecting) {
              print('Disconnecting locally!');
            } else {
              print('Disconnected remotely!');
            }
            if (mounted) {
              setState(() {});
            }
          });
        }).catchError((error) {
          print('Cannot connect, exception occurred');
          print(error);
        });
        show('设备连接结束');

        setState(() => _isButtonUnavailable = false);
      }
    }
  }

  /// 断开连接
  void _disconnect() async {
    setState(() {
      // _isButtonUnavailable = true;
      //清空初始数据列表
      initDataList.clear();
      finalDataList.clear();
    });

    await connection!.close();
    show('设备断开连接');
    if (!connection!.isConnected) {
      setState(() {
        _connected = false;
        _isButtonUnavailable = false;
      });
    }
  }

  /// 处理数据
  /// 十进制数据转ascii字符串
  /// 然后将ascii字符串分割，还原成一个一个int数据添加进finalDataList
  void convertData() async {
    isConvertingData = true;
    String tempDataToString = '';
    List tempDataList = [];

    tempDataToString += ascii.decode(initDataList);

    for (int i = 1; i <= 17; i = i + 2) {
      var temp = tempDataToString.split(" ")[i];
      // print(temp + "----" + i.toString());
      int tempInt = int.parse(temp);
      tempDataList.add(tempInt);
    }
    // print(tempDataList);

    //更新数据，并且判断是否报警
    if (mounted) {
      setState(() {
        dataToString = tempDataToString;
        finalDataList = tempDataList;
        warn1 = finalDataList[0] >= finalDataList[6];
        warn2 = finalDataList[1] >= finalDataList[7];
        warn3 = finalDataList[5] >= finalDataList[8];
      });
    }

    //延迟0.5秒开锁
    Future.delayed(const Duration(milliseconds: 500), () {
      isConvertingData = false;
    });
  }

  ///弹窗
  Future show(String s) {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(s),
            actions: <Widget>[
              TextButton(
                child: const Text("返回"),
                onPressed: () => Navigator.of(context).pop(), // 关闭对话框
              ),
            ],
          );
        });
  }

  ///构建ui
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("蓝牙天气检测工具"),
        actions: [
          //蓝牙开关
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("蓝牙开关"),
              Switch(
                  value: _bluetoothState.isEnabled,
                  activeColor: Colors.white,
                  onChanged: (bool value) async {
                    if (value) {
                      // 开启
                      await FlutterBluetoothSerial.instance.requestEnable();
                    } else {
                      // 关闭
                      await FlutterBluetoothSerial.instance.requestDisable();
                    }
                    // 更新匹配设备列表
                    await getPairedDevices();
                    // 按钮可用
                    _isButtonUnavailable = false;
                    //如果正在连接,先断开连接
                    if (_connected) {
                      _disconnect();
                    }
                  }),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 35),

          //下拉按钮显示蓝牙设备,编写选择逻辑
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton(
                items: _getDeviceItems(),
                onChanged: (value) {
                  if (value != null) {
                    _device = value as BluetoothDevice;
                    setState(() {});
                  }
                },
                value: _devicesList.isNotEmpty ? _device : null,
              ),
              TextButton(
                onPressed: _isButtonUnavailable
                    ? null
                    : _connected
                        ? _disconnect
                        : _connect,
                child: Text(_connected ? '断开连接' : '连接蓝牙'),
              )
            ],
          ),
          const SizedBox(height: 15),
          //实时数据
          Column(
            children: [
              _buildDataTitle("温度", finalDataList.isNotEmpty ? finalDataList[0].toString() + '℃' : "0℃"),
              _buildDataTitle("相对湿度", finalDataList.isNotEmpty ? finalDataList[1].toString() + '%rh' : "0%rh"),
              _buildDataTitle("风速", finalDataList.isNotEmpty ? finalDataList[2].toString() + 'mls' : "0m/s"),
              _buildDataTitle("光照强度", finalDataList.isNotEmpty ? finalDataList[3].toString() + 'Lux' : "0Lux"),
              _buildDataTitle("大气压强", finalDataList.isNotEmpty ? finalDataList[4].toString() + 'hpa' : "0hpa"),
              _buildDataTitle("PM2.5", finalDataList.isNotEmpty ? finalDataList[5].toString() + 'ug' : "0ug"),
            ],
          ),
          const SizedBox(height: 30),
          //阈值数据
          Column(
            children: [
              _buildDataTitle("温度阈值", finalDataList.isNotEmpty ? finalDataList[6].toString() + '℃' : "0℃"),
              _buildDataTitle("湿度阈值", finalDataList.isNotEmpty ? finalDataList[7].toString() + '%rh' : "0%rh"),
              _buildDataTitle("PM2.5阈值", finalDataList.isNotEmpty ? finalDataList[8].toString() + 'ug' : "0ug"),
            ],
          ),

          const SizedBox(height: 20),
          //发送按钮
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildSendButton(0),
            _buildSendButton(1),
            _buildSendButton(2),
            _buildSendButton(3),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildSendButton(4),
            _buildSpecialSendButton(5, 1),
            _buildSpecialSendButton(6, 2),
          ]),
          const SizedBox(height: 20),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWarningButton(warn1, "温度超标", "温度安全"),
              _buildWarningButton(warn2, "湿度超标", "湿度安全"),
              _buildWarningButton(warn3, "PM2.5超标", "PM2.5安全"),
            ],
          )
        ],
      ),
    );
  }

  ///数据标题ui
  Widget _buildDataTitle(String title, String data) {
    double _width = 115;
    double _height = 30;
    TextStyle _textStyle = const TextStyle(fontSize: 15);
    BoxDecoration _boxDecoration = BoxDecoration(border: Border.all(color: Colors.blue, width: 1));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          alignment: Alignment.center,
          decoration: _boxDecoration,
          width: _width,
          height: _height,
          child: Text(
            title,
            style: _textStyle,
          ),
        ),
        Container(
          alignment: Alignment.center,
          decoration: _boxDecoration,
          width: _width,
          height: _height,
          child: Text(
            data,
            style: _textStyle,
          ),
        ),
      ],
    );
  }

  ///普通发送按钮ui
  Widget _buildSendButton(int message) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: ElevatedButton(
        onPressed: _connected ? () => _sendMessage(message) : null,
        child: Text("按钮" + message.toString()),
      ),
    );
  }

  //用于特色发送按键变色的变量
  Color changeColor = Colors.green;
  Color changeColor2 = Colors.green;

  ///特殊发送按钮ui
  Widget _buildSpecialSendButton(int message, int colorInt) {
    return GestureDetector(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4.0),
            color: _connected
                ? colorInt == 1
                    ? changeColor
                    : changeColor2
                : Colors.grey,
            boxShadow: const [
              //阴影
              BoxShadow(color: Colors.black54, offset: Offset(2.0, 2.0), blurRadius: 4.0),
            ],
          ),
          width: 60,
          height: 35,
          margin: const EdgeInsets.all(10),
          alignment: Alignment.center,
          child: Text(
            "按钮" + message.toString(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        onTapDown: (e) {
          if (_connected) {
            _sendMessage(message);
            if (colorInt == 1) {
              setState(() {
                changeColor = Colors.grey;
              });
            }
            if (colorInt == 2) {
              setState(() {
                changeColor2 = Colors.grey;
              });
            }
          }
        },
        onTapUp: (e) {
          if (_connected) {
            _sendMessage(7);
            if (colorInt == 1) {
              setState(() {
                changeColor = Colors.green;
              });
            }
            if (colorInt == 2) {
              setState(() {
                changeColor2 = Colors.green;
              });
            }
          }
        });
  }

  ///报警ui
  Widget _buildWarningButton(bool check, String warn, String safe) {
    return TextButton.icon(
      icon: Icon(
        check ? Icons.dangerous : Icons.health_and_safety,
        color: check ? Colors.red : Colors.green,
        size: 32,
      ),
      label: Text(
        check ? warn : safe,
        style: TextStyle(color: check ? Colors.red : Colors.green, fontSize: 15),
      ),
      onPressed: null,
    );
  }
}
