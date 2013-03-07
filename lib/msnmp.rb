# coding: us-ascii

class String
  unless ''.respond_to? :getbyte
    def getbyte idx
      self[idx]
    end
  end
end

module BER
  extend BER

  def enc tag, val
    case tag
    when 0x02
      return enc_int(val)
    when 0x04
      return enc_str(val)
    end
  end

  def enc_len n
    if n < 128 then
      return n.chr
    end
    e_len = ''
    while n > 0
      e_len = (n & 0xff).chr + e_len
      n = n >> 8
    end
    return (e_len.size | 0x80).chr + e_len
  end

  def enc_int n
    ebuf = ''
    if n < 0 then
      begin
        ebuf = (n & 0xff).chr + ebuf
        n = n >> 8
      end until (n == -1) and (ebuf.getbyte(0) & 0x80 == 0x80)
    else
      begin
        ebuf = (n & 0xff).chr + ebuf
        n = n >> 8
      end while n > 0
    end
    return "\x02" + enc_len(ebuf.size) + ebuf
  end

  def enc_str s
    return "\x04" + enc_len(s.size) + s
  end

  def enc_a_oid a
    a.shift; a.shift
    e = '+' # 1.3
    until a.empty?
      subid = a.shift.to_i
      s = ''
      if subid == 0 then
        e += "\x00"
      else
        while subid > 0
          if s.empty?
            s = (subid & 0x7f).chr + s
          else
            s = (subid & 0x7f | 0x80).chr + s
          end
          subid = subid >> 7
        end
        e += s
      end
    end
    e
  end

  def enc_v_oid oid
    a = oid.split('.')
    enc_a_oid a
  end

  def enc_oid oid
    e = enc_v_oid oid
    return "\x06" + enc_len(e.size) + e
  end

  def enc_oid_list oid_list
    s = ''
    for e in oid_list
      vb = enc_oid(e) + "\x05\x00" # BER.enc_null
      s = s + "\x30" + enc_len(vb.size) + vb
    end
    varbind = "\x30" + enc_len(s.size) + s
  end

  def enc_varbind enoid
    s = "\x06" + enc_len(enoid.size) + enoid + "\x05\x00"
    s = "\x30" + enc_len(s.size) + s
    return "\x30" + enc_len(s.size) + s
  end

  def cat_enoid enoids
    s = ''
    for enoid in enoids
      vb = "\x06" + enc_len(enoid.size) + enoid + "\x05\x00"
      s = s + "\x30" + enc_len(vb.size) + vb
    end
    varbind = "\x30" + enc_len(s.size) + s
  end

  def dec_oid msg
    msg = msg.clone
    if msg.getbyte(0) == 0x2b
      oid = [1, 3]
      msg.slice! 0
    else
      oid = []
    end
    until msg.empty?
      c = msg.getbyte 0
      msg.slice! 0
      if c > 127
        id = 0
        while c > 127
          id = (id << 7) + (c & 0x7f)
          c = msg.getbyte 0
          msg.slice! 0
        end
        id = (id << 7) + c
        oid.push id
      else
	oid.push c
      end
    end
    return oid
  end

  def dec_int s
    if (s.getbyte(0) & 0x80) == 0x80
      n = -1
    else
      n = 0
    end
    while s.size > 0
      n = n << 8 |  s.getbyte(0)
      s = s[1..-1]
    end
    return n
  end

  def dec_cnt s
    n = 0
    while s.size > 0
      #n = n << 8 | s.getbyte(0)
      n = n * 256 + s.getbyte(0)
      s = s[1..-1]
    end
    return n
  end

  def tlv data
    tag = data.getbyte 0
    if (len = data.getbyte(1)) < 128
      val = data[2, len]
      remain = data[(len + 2)..-1]
    elsif len == 0x81
      len = data.getbyte 2
      val = data[3, len]
      remain = data[(len + 3)..-1]
    else
      n = len & 0x7f
      len = 0
      for i in 1..n
        len = len * 256 + data.getbyte(i + 1)
      end
      val = data[n + 2, len]
      remain = data[(len + n + 2).. -1]
    end
    return tag, val, remain
  end

  def dec_msg msg
    if msg[1, 1] < "\x80"
      idx = msg.getbyte(6) + 7
      pdutype, pdu, msg = tlv msg[idx..-1]
    elsif msg[1, 1] == "x81"
      idx = msg.getbyte(7) + 8
      pdutype, pdu, msg = tlv msg[idx..-1]
    else
      tag, val, msg = tlv msg
      tag, ver, msg = tlv val
      tag, comm, msg = tlv msg
      pdutype, pdu, msg = tlv msg
    end
    idlen = pdu.getbyte 1
    enc_reqid = pdu[0, idlen + 2]
    error_status = pdu.getbyte(idlen + 4)
    error_index = pdu.getbyte(idlen + 7)
    tag, varbind, msg = tlv pdu[idlen+8..-1]
    return enc_reqid, error_status, error_index, varbind
  end

  def dec_varbind_block msg
    while msg.size > 0
      tag,val,msg=tlv(msg)
      tag,val1,msg0=tlv(val)
      tag,val2,msg1=tlv(msg0)
      case tag
      when 0x02
        val2=dec_int(val2)
      when 0x05 #Null
        val2=nil
      when 0x06 #OID
        #val2=dec_oid(val2)
      when 0x40 # IP Address
        val2 = val2.unpack('CCCC').join('.')
      when 0x41, 0x42, 0x43 #Counter or Gauge or Tick
        val2 = dec_cnt val2
      when 0x46 #Counter64
	val2 = dec_cnt val2
      when 0x80
        next # skip
      end
      yield val1, tag, val2
    end
  end

  def dec_varbind msg
    list=[]
    val1 = tag = val2 = nil #XXX
    dec_varbind_block(msg) {|val1, tag, val2|
      list.push([val1,tag,val2])
    }
    return list
  end
end

class SNMP
  OIDS = {
    'iso'=>'1',
    'org'=>'1.3',
    'dod'=>'1.3.6',
    'internet'=>'1.3.6.1',
    'directory'=>'1.3.6.1.1',
    'mgmt'=>'1.3.6.1.2',
    'mib-2'=>'1.3.6.1.2.1',
    'system'=>'1.3.6.1.2.1.1',
    'sysDescr'=>'1.3.6.1.2.1.1.1',
    'sysObjectID'=>'1.3.6.1.2.1.1.2',
    'sysUpTime'=>'1.3.6.1.2.1.1.3',
    'sysContact'=>'1.3.6.1.2.1.1.4',
    'sysName'=>'1.3.6.1.2.1.1.5',
    'sysLocation'=>'1.3.6.1.2.1.1.6',
    'sysServices'=>'1.3.6.1.2.1.1.7',

    'interfaces'=>'1.3.6.1.2.1.2',
    'ifNumber'=>'1.3.6.1.2.1.2.1',
    'ifTable'=>'1.3.6.1.2.1.2.2',
    'ifEntry'=>'1.3.6.1.2.1.2.2.1',
    'ifIndex'=>'1.3.6.1.2.1.2.2.1.1',
    'ifInOctets'=>'1.3.6.1.2.1.2.2.1.10',
    'ifInUcastPkts'=>'1.3.6.1.2.1.2.2.1.11',
    'ifInNUcastPkts'=>'1.3.6.1.2.1.2.2.1.12',
    'ifInDiscards'=>'1.3.6.1.2.1.2.2.1.13',
    'ifInErrors'=>'1.3.6.1.2.1.2.2.1.14',
    'ifInUnknownProtos'=>'1.3.6.1.2.1.2.2.1.15',
    'ifOutOctets'=>'1.3.6.1.2.1.2.2.1.16',
    'ifOutUcastPkts'=>'1.3.6.1.2.1.2.2.1.17',
    'ifOutNUcastPkts'=>'1.3.6.1.2.1.2.2.1.18',
    'ifOutDiscards'=>'1.3.6.1.2.1.2.2.1.19',
    'ifDescr'=>'1.3.6.1.2.1.2.2.1.2',
    'ifOutErrors'=>'1.3.6.1.2.1.2.2.1.20',
    'ifOutQLen'=>'1.3.6.1.2.1.2.2.1.21',
    'ifSpecific'=>'1.3.6.1.2.1.2.2.1.22',
    'ifType'=>'1.3.6.1.2.1.2.2.1.3',
    'ifMtu'=>'1.3.6.1.2.1.2.2.1.4',
    'ifSpeed'=>'1.3.6.1.2.1.2.2.1.5',
    'ifPhysAddress'=>'1.3.6.1.2.1.2.2.1.6',
    'ifAdminStatus'=>'1.3.6.1.2.1.2.2.1.7',
    'ifOperStatus'=>'1.3.6.1.2.1.2.2.1.8',
    'ifLastChange'=>'1.3.6.1.2.1.2.2.1.9',

    'ipAddrTable'=>'1.3.6.1.2.1.4.20',
    'ipAddrEntry'=>'1.3.6.1.2.1.4.20.1',
    'ipAdEntIfIndex'=>'1.3.6.1.2.1.4.20.1.2',
    'ipAdEntNetMask'=>'1.3.6.1.2.1.4.20.1.3',
    'ipNetToMediaIfIndex'=>'1.3.6.1.2.1.4.22.1.1',
    'ipNetToMediaPhysAddress'=>'1.3.6.1.2.1.4.22.1.2',
    'ipNetToMediaNetAddress'=>'1.3.6.1.2.1.4.22.1.3',
    'ipNetToMediaType'=>'1.3.6.1.2.1.4.22.1.4',

    'ifMIB'=>'1.3.6.1.2.1.31',
    'ifXEntry'=>'1.3.6.1.2.1.31.1.1.1',
    'ifName'=>'1.3.6.1.2.1.31.1.1.1.1',
    'ifInMulticastPkts'=>'1.3.6.1.2.1.31.1.1.1.2',
    'ifInBroadcastPkts'=>'1.3.6.1.2.1.31.1.1.1.3',
    'ifOutMulticastPkts'=>'1.3.6.1.2.1.31.1.1.1.4',
    'ifOutBroadcastPkts'=>'1.3.6.1.2.1.31.1.1.1.5',
    'ifHCInOctets'=>'1.3.6.1.2.1.31.1.1.1.6',
    'ifHCInUcastPkts'=>'1.3.6.1.2.1.31.1.1.1.7',
    'ifHCInMulticastPkts'=>'1.3.6.1.2.1.31.1.1.1.8',
    'ifHCInBroadcastPkts'=>'1.3.6.1.2.1.31.1.1.1.9',
    'ifHCOutOctets'=>'1.3.6.1.2.1.31.1.1.1.10',
    'ifHCOutUcastPkts'=>'1.3.6.1.2.1.31.1.1.1.11',
    'ifHCOutMulticastPkts'=>'1.3.6.1.2.1.31.1.1.1.12',
    'ifHCOutBroadcastPkts'=>'1.3.6.1.2.1.31.1.1.1.13',
    'ifLinkUpDownTrapEnable'=>'1.3.6.1.2.1.31.1.1.1.14',
    'ifHighSpeed'=>'1.3.6.1.2.1.31.1.1.1.15',
    'ifPromiscuousMode'=>'1.3.6.1.2.1.31.1.1.1.16',
    'ifConnectorPresent'=>'1.3.6.1.2.1.31.1.1.1.17',
    'ifAlias'=>'1.3.6.1.2.1.31.1.1.1.18',

    'experimental'=>'1.3.6.1.3',
    'private'=>'1.3.6.1.4',
    'enterprises'=>'1.3.6.1.4.1',
  }
  ROIDS = {}
  RECV_SIZE = 2000

  attr_reader :sock
  attr_accessor :state, :numeric

  def self.add_oid sym, oid
    OIDS[sym] = oid
  end

  def self.update h
    OIDS.merge! h
  end

  def initialize host, port=nil
    port ||= 161
    if ROIDS.empty?
      for sym, oid in OIDS
        ROIDS[BER.enc_v_oid(oid)] = sym
      end
    end
    @host = host
    @port = port
    @request_id = 1000
    @retries = 3
    @timeout = 4
    @ver = "\x02\x01\x00" # INT: 0 (ver 1)
    @community = "\x04\x06public"
    @numeric = false
    @state = :IDLE
    @sock = nil
  end

  def connect
    @sock = UDPSocket.new
    @sock.connect @host, @port
  end

  def close
    @sock.close
  end

  def version=(ver)
    ver = {'1'=>0, '2c'=>1}[ver] || 0
    @ver = BER.enc_int ver
  end

  def community=(community)
    @community = BER.enc_str community
  end

  def enoid2name enoid
    a = BER.dec_oid enoid
    n = a.size
    n0 = n

    while n > 1
      if (s = ROIDS[BER.enc_a_oid(a[0, n])])
        return ([s] + a[n, n0-n]).join('.')
      end
      n -= 1
    end
    s || a.join('.')
  end

  def make_msg cmd, err_index, varbind
    @request_id += 1
    @enc_request_id = BER.enc_int @request_id
    s = @enc_request_id + "\x02\x01\x00" + err_index + varbind
    s = @ver + @community + cmd + BER.enc_len(s.size) + s
    s = "\x30" + BER.enc_len(s.size) + s
  end

  def make_req st, arg
    case st
    when :GETBULK_REQ
      vb = "\x06" + BER.enc_len(arg.size) + arg + "\x05\x00"
      vb = "\x30" + BER.enc_len(vb.size) + vb
      varbind = "\x30" + BER.enc_len(vb.size) + vb
      s = make_msg "\xa5", "\x02\x01\x0c", varbind
    when :GETNEXT_REQ
      vb = "\x06" + BER.enc_len(arg.size) + arg + "\x05\x00"
      vb = "\x30" + BER.enc_len(vb.size) + vb
      varbind = "\x30" + BER.enc_len(vb.size) + vb
      s = make_msg "\xa1", "\x02\x01\x00", varbind
    when :GET_REQ
      s = make_msg "\xa0", "\x02\x01\x00", arg
    end
    s
  end

  def walk_start enoid, &cb
    @req_enoid = enoid
    @cb = cb
    @state = (@ver == "\002\001\001") ? :GETBULK_REQ : :GETNEXT_REQ
  end

  def _walk enoid, &cb
    walk_start enoid, &cb
    req_loop enoid
  end

  def walk oid, &cb
    noid = OIDS[oid] || oid
    enoid = BER.enc_v_oid noid
    _walk(enoid) {|enoid, tag, val|
      oid = @numeric ? (BER.dec_oid(enoid).join('.')) : (enoid2name enoid)
      cb.call oid, tag, val
    }
  end

  def get_start varbind, &cb
    @req_enoid = ''
    @cb = cb
    @state = :GET_REQ
  end

  def get_varbind varbind, &cb
    get_start varbind, &cb
    req_loop varbind
  end

  def get oid_list, &cb
    oids = oid_list.map {|s| BER.enc_v_oid(OIDS[s]||s)}
    varbind = BER.cat_enoid oids
    get_varbind(varbind) {|enoid, tag, val|
      oid = @numeric ? (BER.dec_oid(enoid).join('.')) : (enoid2name enoid)
      cb.call oid, tag, val
    }
  end

  def req_loop arg
    connect unless @sock
    until @state == :SUCCESS or @state == :IDLE
      s = make_req @state, arg
      @retry_count = 0
      while true
        @sock.send s, 0
        if (a = IO.select([@sock], nil, nil, @timeout))
          msg = @sock.recv RECV_SIZE, 0
          arg = recv_msg msg
          if arg
            @state = :SUCCESS if @state == :GET_REQ
            break
          end
        else
          if (@retry_count += 1) >= @retries
            @state = :IDLE
            return
          end
        end
      end
    end
  end

  def recv_msg msg
    enc_request_id, @error_status, @error_index, varbind = BER.dec_msg msg
    return unless enc_request_id == @enc_request_id
    unless @error_status == 0
      @state = :IDLE
      return
    end

    vars = BER.dec_varbind varbind
    for var in vars
      if (var[1] != 130) and var[0].index(@req_enoid) #130=endOfMibView
        @cb.call(*var)
      else
        @state = :SUCCESS
      end
    end
    enoid = vars[-1][0]
  end
end
