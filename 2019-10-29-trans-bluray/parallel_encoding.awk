#!/usr/bin/gawk -E
@load "filefuncs"

function assert(condition, string) {
    if (! condition) {
        printf("assertion failed: %s\n",
               string) > "/dev/stderr"
        _assert_exit = 1
        exit 1
    }
}

function getopt(argc, argv, options,    thisopt, i) {
    if (length(options) == 0)    # no options given
        return -1

    if (argv[Optind] == "--") {  # all done
        Optind++
        _opti = 0
        return -1
    } else if (argv[Optind] !~ /^-[^:[:space:]]/) {
        _opti = 0
        return -1
    }
    if (_opti == 0)
        _opti = 2
    thisopt = substr(argv[Optind], _opti, 1)
    Optopt = thisopt
    i = index(options, thisopt)
    if (i == 0) {
        if (Opterr)
            printf("%c -- invalid option\n", thisopt) > "/dev/stderr"
        if (_opti >= length(argv[Optind])) {
            Optind++
            _opti = 0
        } else
            _opti++
        return "?"
    }
    if (substr(options, i + 1, 1) == ":") {
        # get option argument
        if (length(substr(argv[Optind], _opti + 1)) > 0)
            Optarg = substr(argv[Optind], _opti + 1)
        else
            Optarg = argv[++Optind]
        _opti = 0
    } else
        Optarg = ""
    if (_opti == 0 || _opti >= length(argv[Optind])) {
        Optind++
        _opti = 0
    } else
        _opti++
    return thisopt
}

function basename(path) {
    n = patsplit(path,f,"[^/]+")
    if (n)
        return f[n]
    else
        return path
}

function usage(option, optarg) {
    print "Bad argument:",option,optarg
    print "Usage:", ARGV[1], "-i 'Path to input blu-ray directory or MKV file' [-l Preferred three letter language ISO 639-2 code (spa)] [-o 'Path to output MKV file' (input_title_name.mkv)] [-t threads_per_process (min(nproc,8))]"
    exit 1
}

function printSub(lang,sub_stream) {
    printf "%s,%s\n",lang,sub_stream[lang]
}

function printAudio(lang,al_stream,al_bitrate,al_channels,al_codec,al_cname) {
    printf "%s,%s,%s,%s,%s\n",lang,al_stream[lang],al_bitrate[lang],al_channels[lang],\
al_codec[lang],al_cname[lang]
}

function setVideo(lang,vl_stream,vl_bitrate,streamId,bitrate) {
    if (length(lang) == 0) lang = "empty"
    vl_stream[lang] = streamId
    vl_bitrate[lang] = bitrate
}

function setAudio(lang,streamId,bitrate,channels,codec,cname,profile) {
    al_stream[lang] = streamId
    al_bitrate[lang] = bitrate
    al_channels[lang] = channels
    al_codec_short[lang] = codec
    al_codec_long[lang] = cname
    al_profile[lang] = profile
}

function setSub(lang,streamId,codec,cname,frames) {
    sl_stream[lang] = streamId
    sl_frames[lang] = frames
    sl_codec_short[lang] = codec
    sl_codec_long[lang] = cname
}

function getOpusChannelFamily(channels) {
    if (channels <= 2) return 0
    else return 1
}

function max(a,b) {
    return (a > b) ? a : b;
}

function getBitrate(curr_bitrate) {
    if (curr_bitrate !~ /N\/A/) return int(max(1024000,curr_bitrate)/2)
    else return 512000
}

function setStartDuration(chunk,start,duration) {
    total_subs = gsub(/SEGSTART/,start,chunk)
    assert(total_subs == 1, sprintf("FFMPEG segment start for chunk % has not been put.",idx))

    total_subs = gsub(/SEGDUR/,duration,chunk)
    assert(total_subs == 1, sprintf("FFMPEG segment duration for chunk %s has not been put.",idx))
    return chunk
}

function multiprocess_encoding_vp9_8bit() {
    tmp_dir_name = videos_dir "/" filename "_tmpdir_" PROCINFO["pid"]
    concat_list = tmp_dir_name "/" filename "_concat_files.dat"
    system(("mkdir -p " tmp_dir_name))
    if (max_process_threads == 0)
        max_process_threads = (hwthreads < THREADS_CCX) ? hwthreads : THREADS_CCX
    processes = int(hwthreads / max_process_threads)
    duration_fractions[0] = max_process_threads / hwthreads
    process_threads[0] = max_process_threads
    for (i=1;i<processes;i++) {
        duration_fractions[i] = max_process_threads / hwthreads
        process_threads[i] = max_process_threads
    }
    
    if ((rem = hwthreads % max_process_threads) != 0) {
        duration_fractions[processes] = rem / hwthreads
        process_threads[processes] = rem
        processes++
    }
    cmd_file = tmp_dir_name "/" filename "_split_params.csv"
    for (i=0;i<processes;i++) {
        if (i == 0) start = 0
        else start = end[i-1]
        if (i == processes-1) chunk_duration = duration - start
        else {
            chunk_duration = duration * duration_fractions[i]
            end[i] = chunk_duration + start
        }
        idx = sprintf("%03d",i)
        av_output_file = tmp_dir_name "/" filename "_chunk_" idx ".mkv"
	
        ffmpeg_av_chunk = ffmpeg_av
        ffmpeg_av_chunk = setStartDuration(ffmpeg_av_chunk,start,duration)

        ffmpeg_av_chunk = ffmpeg_av_chunk \
                        " -i " "'INPUT_FILE'" \
                        " -vcodec libvpx-vp9 -row-mt 1 -tile-rows 2 "\
                        " -tile-columns 4 -cpu-used 0 -crf 18 -b:v 0 "\
                        " -aq-mode 2 -auto-alt-ref 1 -lag-in-frames 25 "\
                        " -slices 4 -qmin 0 -qmax 33 -g 250 " EXTRAPARAMS\
                        " -frame-parallel 1 -tune-content 2 -level 5.1 "\
                        " -threads " process_threads[i] v_maps a_maps\
                        " FFMPEGPASS "\
                        "-y " "'OUTPUT_FILE'"
        total_subs = gsub(/[[:space:]]+/," ",ffmpeg_av_chunk)
        total_subs = gsub(/INPUT_FILE/,input_file,ffmpeg_av_chunk)
        total_subs = gsub(/OUTPUT_FILE/,av_output_file,ffmpeg_av_chunk)

        ffmpeg_pass1 = ffmpeg_av_chunk
        ffmpeg_pass2 = ffmpeg_av_chunk

        total_subs = gsub(/FFMPEGPASS/,"-pass 1 -an -passlogfile '" av_output_file "'",ffmpeg_pass1)
        assert(total_subs == 1, "FFMPEG pass 1 could not be configured")

        total_subs = gsub(/FFMPEGPASS/,"-pass 2 -passlogfile '" av_output_file "'",ffmpeg_pass2)
        assert(total_subs == 1, "FFMPEG pass 2 could not be configured")
        print ffmpeg_pass1";"ffmpeg_pass2 > cmd_file
    }
    parallel_cmd = "/usr/bin/time -f %e parallel --linebuffer --no-run-if-empty -v :::: " cmd_file
    res = system(parallel_cmd)
    assert(res == 0, "GNU Parallel exit status was not zero.")
    for (i=0;i<processes;i++) {
        idx = sprintf("%03d",i)
        file_chunk_name = tmp_dir_name "/" filename "_chunk_" idx ".mkv"
        assert(! stat(file_chunk_name,fstat), "No compressed AV files have been produced. Aborting.")
        print "file '"file_chunk_name"'" > concat_list
    }

    ffmpeg_concat_cmd = "ffmpeg -f concat -safe 0 -i " concat_list " -i " "'"input_file"'" " -map 0 -c copy " s_maps " -map_metadata 1 -map_chapters 1 -c copy -y " "'"transcoded_file"'"
    res = system(ffmpeg_concat_cmd)
    assert(res == 0, "FFMPEG exit status was not zero.")
}

function single_process_encoding_x265_8bit() {
    ffmpeg_av = setStartDuration(ffmpeg_av,0,duration)
    gsub(/-map 1:/,"-map 0:",s_maps)
    ffmpeg_cmd = ffmpeg_av " -i " "'INPUT_FILE'" \
        " -vcodec libx265 -qmin 0 -qmax 46 -crf 20 " \
        " -profile:v main -preset:v slower -tune grain -x265-params " \
        "  ctu=32:aq-mode=3:aq-strength=1:cutree=1:rskip=1 " \
        EXTRAPARAMS " " \
        v_maps a_maps s_maps " -scodec copy -map_metadata 0 " \
        " -y " "'TRANSCODED_FILE'"
    total_subs = gsub(/[[:space:]]+/," ",ffmpeg_cmd)
    total_subs = gsub(/INPUT_FILE/,input_file,ffmpeg_cmd)
    total_subs = gsub(/TRANSCODED_FILE/,transcoded_file,ffmpeg_cmd)
    print ffmpeg_cmd
    system(ffmpeg_cmd)
}

BEGIN {
   ISO6392CODES= "aar abk ace ach ada ady afa afh afr ain aka akk alb sqi ale alg \
                  alt amh ang anp apa ara arc arg arm hye arn arp art arw asm \
                  ast ath aus ava ave awa aym aze bad bai bak bal bam ban baq \
                  eus bas bat bej bel bem ben ber bho bih bik bin bis bla bnt \
                  tib bod bos bra bre btk bua bug bul bur mya byn cad cai car \
                  cat cau ceb cel cze ces cha chb che chg chi zho chk chm chn \
                  cho chp chr chu chv chy cmc cnr cop cor cos cpe cpf cpp cre \
                  crh crp csb cus wel cym cze ces dak dan dar day del den ger \
                  deu dgr din div doi dra dsb dua dum dut nld dyu dzo efi egy \
                  eka gre ell elx eng enm epo est baq eus ewe ewo fan fao per \
                  fas fat fij fil fin fiu fon fre fra fre fra frm fro frr frs \
                  fry ful fur gaa gay gba gem geo kat ger deu gez gil gla gle \
                  glg glv gmh goh gon gor got grb grc gre ell grn gsw guj gwi \
                  hai hat hau haw heb her hil him hin hit hmn hmo hrv hsb hun \
                  hup arm hye iba ibo ice isl ido iii ijo iku ile ilo ina inc \
                  ind ine inh ipk ira iro ice isl ita jav jbo jpn jpr jrb kaa \
                  kab kac kal kam kan kar kas geo kat kau kaw kaz kbd kha khi \
                  khm kho kik kin kir kmb kok kom kon kor kos kpe krc krl kro \
                  kru kua kum kur kut lad lah lam lao lat lav lez lim lin lit \
                  lol loz ltz lua lub lug lui lun luo lus mac mkd mad mag mah \
                  mai mak mal man mao mri map mar mas may msa mdf mdr men mga \
                  mic min mis mac mkd mkh mlg mlt mnc mni mno moh mon mos mao \
                  mri may msa mul mun mus mwl mwr bur mya myn myv nah nai nap \
                  nau nav nbl nde ndo nds nep new nia nic niu dut nld nno nob \
                  nog non nor nqo nso nub nwc nya nym nyn nyo nzi oci oji ori \
                  orm osa oss ota oto paa pag pal pam pan pap pau peo per fas \
                  phi phn pli pol pon por pra pro pus qaa que raj rap rar roa \
                  roh rom rum ron rum ron run rup rus sad sag sah sai sal sam \
                  san sas sat scn sco sel sem sga sgn shn sid sin sio sit sla \
                  slo slk slo slk slv sma sme smi smj smn smo sms sna snd snk \
                  sog som son sot spa alb sqi srd srn srp srr ssa ssw suk sun \
                  sus sux swa swe syc syr tah tai tam tat tel tem ter tet tgk \
                  tgl tha tib bod tig tir tiv tkl tlh tli tmh tog ton tpi tsi \
                  tsn tso tuk tum tup tur tut tvl twi tyv udm uga uig ukr umb \
                  und urd uzb vai ven vie vol vot wak wal war was wel cym wen \
                  wln wol xal xho yao yap yid yor ypk zap zbl zen zgh zha chi \
                  zho znd zul zun zza"
    FPAT="([^,]+)|([^,]+=\"[^\"]+\")"
    THREADS_CCX=8
    ffmpeg_av="ffmpeg -ss SEGSTART -t SEGDUR "
    ffmpeg_s="ffmpeg "
    a_maps=""
    v_maps=""
    s_maps=""
    intput_file = ""
    output_file = ""
    pref_lang = ""
    max_process_threads = 0
    Optind = 1
    Opterr = 1
    while ((res = getopt(ARGC, ARGV, ":i:o:l:t:x:") != -1)) {
        switch (Optopt) {
            case "i":
                input_file = Optarg
                if (stat(input_file,fstat)) usage(Optopt,Optarg)
                break
            case "o":
                output_file = Optarg
                if (output_file !~ /.mkv/) usage(Optopt,Optarg)
                break
            case "l":
                pref_lang = Optarg
                if (ISO6392CODES !~ pref_lang) usage(Optopt,Optarg)
                break
            case "t":
                if (Optarg !~ /0*[1-9]+/) max_process_threads = Optarg
                break
            case "x":
                EXTRAPARAMS = Optarg
                break
            default:
                usage(Optopt,Optarg)
                break
        }
    }
    
    if (length(pref_lang) == 0) pref_lang = "spa"
    "nproc" | getline hwthreads
    "xdg-user-dir VIDEOS" | getline videos_dir
    filename = gensub(/ /,"_","g",gensub(/\.mkv$/,"","g",basename(input_file))) "_out"
    if (length(output_file) == 0) transcoded_file = videos_dir "/" filename "_transcoded.mkv"
    else transcoded_file = gensub(/ /,"_","g",output_file)
    ffprobe_cmd = "ffprobe -loglevel quiet -show_streams -show_format -show_chapters -of csv=nk=0 " "'"input_file"'"

    while((ffprobe_cmd | getline) > 0)
    {
        if ($1 ~ /stream/) {
            for (i=2;i<=NF;i++) {
                n = split($i,kv,"=")
                switch (kv[1]) {
                    case "index":
                        streamId = kv[2]
                        break;
                    case "codec_name":
                        codec_short = kv[2]
                        break;
                    case "codec_long_name":
                        codec_long = kv[2]
                        break;
                    case "codec_type":
                        codec_type = kv[2]
                        break;
                    case "profile":
                        profile = kv[2]
                        break;
                    case "codec_time_base":
                        codec_tbase = kv[2]
                        break;
                    case "width":
                        h_res = kv[2]
                        break;
                    case "height":
                        v_res = kv[2]           
                        break;
                    case "display_aspect_ratio":
                        ar = kv[2]
                        break;
                    case "r_frame_rate":
                        fps = kv[2]
                        break;
                    case "pix_fmt":
                        pix_fmt = kv[2]
                        break;
                    case "time_base":
                        tbase = kv[2]
                        break;
                    case "start_pts":
                        start_pts = kv[2]
                        break;
                    case "start_time":
                        start_time = kv[2]
                        break;
                    case "tag:language":
                        lang = kv[2]
                        break;
                    case "sample_rate":
                        freq = kv[2]
                        break;
                    case "channels":
                        channels = kv[2]
                        break;
                    case "channel_layout":
                        channel_distribution = kv[2]
                        break;
                    case "bit_rate":
                        bitrate = kv[2]
                        break;
                    case "tag:NUMBER_OF_FRAMES-eng":
                        frames = kv[2]
                        break;
                    default:
                        break;
                }
            }

            if (codec_type ~ /video/) {
                setVideo(lang,vl_stream, vl_bitrate, streamId, bitrate)
            }

            if (codec_type ~ /audio/) {
                if (lang in al_stream) {
                    if ((streamId != al_stream[lang]) && (al_bitrate[lang] < bitrate) && (al_channels[lang] <= channels) && ( codec_short ~ /dts/ || profile ~ /DTS-HD/)) {
                        setAudio(lang,streamId,bitrate,channels,codec_short,codec_long,profile)
                    }
                } else {
                    setAudio(lang,streamId,bitrate,channels,codec_short,codec_long,profile)
                }
            }
    
            if (codec_type ~ /subtitle/) {
                if (lang in sl_stream) {
                    if (codec_short ~ /hdmv/ && sl_codec_short[lang] !~ /hdmv/) {
                        setSub(lang,streamId,codec_short,codec_long,frames)
                    } else if (codec_short == sl_codec_short[lang] && frames > sl_frames[lang]) {
                        setSub(lang,streamId,codec_short,codec_long,frames)
                    }
                } else setSub(lang,streamId,codec_short,codec_long,frames)
            }

            if (codec_type ~ /chapter/) {}
            if (codec_type ~ /format/) {}
        }
        if ($1 ~ /format/) {
            for (i=2;i<NF;i++) {
                n = split($i,kv,"=")
                switch (kv[1]) {
                    case "duration":
                        duration = kv[2]
                        break;
                    default:
                        break;
                }
            }
        }
    }
    close(ffprobe_cmd)

    ####### END #######
    if (length(vl_stream) > 0) {
        for (vl in vl_stream) {
            v_maps = v_maps " -map 0:" vl_stream[vl] " "
        }
    }
    if (length(al_stream) > 0) {
        current_index = 1
        if (pref_lang in al_stream) {
            a_maps = a_maps " -codec:"current_index " libopus -map 0:"\
                al_stream[pref_lang] " -b:"current_index \
                " " getBitrate(al_bitrate[pref_lang]) " -ac:1 " \
                al_channels[pref_lang] " -mapping_family:"current_index \
                " " getOpusChannelFamily(al_channels[pref_lang]) \
                " -disposition:" al_stream[pref_lang] " default "
            current_index++
        }
        print "Selected audio streams:"
        for (al in al_stream) {
            printf "language=%s,bitrate=%s,channels=%d,codec_short=%s,codec_long=%s,profile=%s\n",al,al_bitrate[al],al_channels[al],al_codec_short[al],al_codec_long[al],al_profile[al]
            if (al != pref_lang) {
                opus_bitrate = getBitrate(al_bitrate[al])
                a_maps = a_maps " -codec:" current_index " libopus -map 0:" al_stream[al] " -b:" current_index " " \
                    opus_bitrate " -ac:" current_index " " al_channels[al] \
                    " -mapping_family:" current_index " " getOpusChannelFamily(al_channels[al]) \
                    " -disposition:" al_stream[al] " none "
                current_index++
            }
        }
    }
    if (length(sl_stream) > 0) {
        print "Selected subtitle streams:"
        if (pref_lang in sl_stream) {
            s_maps = s_maps " -map 1:" sl_stream[pref_lang] " -disposition:" sl_stream[pref_lang] " default "
        }
        printf "language=%s,codec_short=%s,codec_long=%s,frames=%s\n",pref_lang,sl_codec_short[pref_lang],sl_codec_long[pref_lang],sl_frames[pref_lang]
        for (sl in sl_stream) {
            if (!(sl in al_stream) \
                && sl !~ /cat/ \
                && sl !~ /spa/ \
                && sl !~ /eng/) delete sl_stream[sl]
            else if (sl != pref_lang) {
                s_maps = s_maps " -map 1:" sl_stream[sl] " -disposition:" sl_stream[sl] " none "
                printf "language=%s,codec_short=%s,codec_long=%s,frames=%s\n",sl,sl_codec_short[sl],sl_codec_long[sl],sl_frames[sl]
            }
        }
    }

    single_process_encoding_x265_8bit()
    exit 0
}
END {
    if (_assert_exit)
        exit 1
}
