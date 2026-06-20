
// Signed Int64 to FPR
`include "defines.vh"

module int2fpr #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         int2fpr_in_tvalid,
  input  wire [63:0]  int2fpr_in_tdata,

  output wire         int2fpr_out_tvalid,
  output wire [63:0]  int2fpr_out_tdata
);
  
  wire in_tdata_is_0;
  wire in_tdata_is_max_neg;

  wire [63:0] in_unsigned;

  wire        out_sign;
  wire [10:0] out_exp;
  wire [51:0] out_mant;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         int2fpr_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] int2fpr_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         int2fpr_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] int2fpr_out_tdata_reg;
  `endif

  wire [5:0] in_unsigned_loc;
  wire [5:0] in_unsigned_loc_sub_one_trimmed_1;
  wire [5:0] in_unsigned_loc_sub_one_trimmed_2;
  wire [6:0] sub_64_in_unsigned_loc;

  wire [63:0] mantissa_mask;
  wire [63:0] mantissa_int;

  // calculate both, pick the correct one
  wire [51:0] mantissa_trimmed_1; // valid when in_unsigned_loc <= 52
  wire [63:0] mantissa_trimmed_2_full;
  wire        mantissa_trimmed_2_round_bit;
  wire [51:0] mantissa_trimmed_2; // valid when in_unsigned_loc > 52
  wire        incr_exp_for_mant_rounding; // 1 when you need to incr exponent because mantissa rounding caused overflow, else 0



  // signed to unsigned conversion
  // when max negative value, it wont work.
  // for example (3 bit signed), if -4. then ~(-4)+1 = 0, but we need +4.
  assign in_unsigned = (int2fpr_in_tdata[63] == 1'b0) ? int2fpr_in_tdata :
                       (in_tdata_is_max_neg == 1'b1) ? int2fpr_in_tdata : ((~int2fpr_in_tdata) + 1'b1);

  // edge case of input = 0
  assign in_tdata_is_0 = (int2fpr_in_tdata == 64'd0) ? 1'b1 : 1'b0;
  assign in_tdata_is_max_neg = ((int2fpr_in_tdata[62:0] == 63'd0) && (int2fpr_in_tdata[63] == 1'b0)) ? 1'b1 : 1'b0;

  assign out_sign = int2fpr_in_tdata[63];

  // in_unsigned_loc + 1023 (bias)
  // = (in_unsigned_loc - 1) + 1024
  assign out_exp_trimmed_1 = {1'b1, 4'b0, in_unsigned_loc_sub_one_trimmed_1};
  assign out_exp_trimmed_2 = {1'b1, 4'b0, in_unsigned_loc_sub_one_trimmed_2};

  // gives leading 1 in input, with LSB 1 returning index 0 and MSB 1 returning index 63
  leading_one_calc #(
    .DEBUG (DEBUG),
    .N (64),
    .N_BITS (6)
  ) leading_one_calc_inst (
    .loc_din (in_unsigned),
    .loc_dout (in_unsigned_loc)
  );

  assign in_unsigned_loc_sub_one_trimmed_1 = in_unsigned_loc - 1'b1; // trimmed manitssa fits in 52 bits
  assign in_unsigned_loc_sub_one_trimmed_2 = in_unsigned_loc - 1'b1 + incr_exp_for_mant_rounding; // trimmed manitssa greater than 52 bits

  `ifdef MASK_USING_BARREL_SHIFTER
    assign sub_64_in_unsigned_loc = 7'd64 - in_unsigned_loc;
    assign mantissa_mask = 64'hFFFF_FFFF_FFFF_FFFF >> sub_64_in_unsigned_loc;
  `else
    assign mantissa_mask = (in_unsigned_loc == 6'd0)  ? 64'h0000_0000_0000_0000 :   
                          (in_unsigned_loc == 6'd1)  ? 64'h0000_0000_0000_0001 :   
                          (in_unsigned_loc == 6'd2)  ? 64'h0000_0000_0000_0003 :   
                          (in_unsigned_loc == 6'd3)  ? 64'h0000_0000_0000_0007 :   
                          (in_unsigned_loc == 6'd4)  ? 64'h0000_0000_0000_000f :   
                          (in_unsigned_loc == 6'd5)  ? 64'h0000_0000_0000_001f :   
                          (in_unsigned_loc == 6'd6)  ? 64'h0000_0000_0000_003f :   
                          (in_unsigned_loc == 6'd7)  ? 64'h0000_0000_0000_007f :   
                          (in_unsigned_loc == 6'd8)  ? 64'h0000_0000_0000_00ff :   
                          (in_unsigned_loc == 6'd9)  ? 64'h0000_0000_0000_01ff :   
                          (in_unsigned_loc == 6'd10) ? 64'h0000_0000_0000_03ff :   
                          (in_unsigned_loc == 6'd11) ? 64'h0000_0000_0000_07ff :   
                          (in_unsigned_loc == 6'd12) ? 64'h0000_0000_0000_0fff :   
                          (in_unsigned_loc == 6'd13) ? 64'h0000_0000_0000_1fff :   
                          (in_unsigned_loc == 6'd14) ? 64'h0000_0000_0000_3fff :   
                          (in_unsigned_loc == 6'd15) ? 64'h0000_0000_0000_7fff :   
                          (in_unsigned_loc == 6'd16) ? 64'h0000_0000_0000_ffff :   
                          (in_unsigned_loc == 6'd17) ? 64'h0000_0000_0001_ffff :   
                          (in_unsigned_loc == 6'd18) ? 64'h0000_0000_0003_ffff :   
                          (in_unsigned_loc == 6'd19) ? 64'h0000_0000_0007_ffff :   
                          (in_unsigned_loc == 6'd20) ? 64'h0000_0000_000f_ffff :   
                          (in_unsigned_loc == 6'd21) ? 64'h0000_0000_001f_ffff :   
                          (in_unsigned_loc == 6'd22) ? 64'h0000_0000_003f_ffff :   
                          (in_unsigned_loc == 6'd23) ? 64'h0000_0000_007f_ffff :   
                          (in_unsigned_loc == 6'd24) ? 64'h0000_0000_00ff_ffff :   
                          (in_unsigned_loc == 6'd25) ? 64'h0000_0000_01ff_ffff :   
                          (in_unsigned_loc == 6'd26) ? 64'h0000_0000_03ff_ffff :   
                          (in_unsigned_loc == 6'd27) ? 64'h0000_0000_07ff_ffff :   
                          (in_unsigned_loc == 6'd28) ? 64'h0000_0000_0fff_ffff :   
                          (in_unsigned_loc == 6'd29) ? 64'h0000_0000_1fff_ffff :   
                          (in_unsigned_loc == 6'd30) ? 64'h0000_0000_3fff_ffff :   
                          (in_unsigned_loc == 6'd31) ? 64'h0000_0000_7fff_ffff :   
                          (in_unsigned_loc == 6'd32) ? 64'h0000_0000_ffff_ffff :   
                          (in_unsigned_loc == 6'd33) ? 64'h0000_0001_ffff_ffff :   
                          (in_unsigned_loc == 6'd34) ? 64'h0000_0003_ffff_ffff :   
                          (in_unsigned_loc == 6'd35) ? 64'h0000_0007_ffff_ffff :   
                          (in_unsigned_loc == 6'd36) ? 64'h0000_000f_ffff_ffff :   
                          (in_unsigned_loc == 6'd37) ? 64'h0000_001f_ffff_ffff :   
                          (in_unsigned_loc == 6'd38) ? 64'h0000_003f_ffff_ffff :   
                          (in_unsigned_loc == 6'd39) ? 64'h0000_007f_ffff_ffff :   
                          (in_unsigned_loc == 6'd40) ? 64'h0000_00ff_ffff_ffff :   
                          (in_unsigned_loc == 6'd41) ? 64'h0000_01ff_ffff_ffff :   
                          (in_unsigned_loc == 6'd42) ? 64'h0000_03ff_ffff_ffff :   
                          (in_unsigned_loc == 6'd43) ? 64'h0000_07ff_ffff_ffff :   
                          (in_unsigned_loc == 6'd44) ? 64'h0000_0fff_ffff_ffff :   
                          (in_unsigned_loc == 6'd45) ? 64'h0000_1fff_ffff_ffff :   
                          (in_unsigned_loc == 6'd46) ? 64'h0000_3fff_ffff_ffff :   
                          (in_unsigned_loc == 6'd47) ? 64'h0000_7fff_ffff_ffff :   
                          (in_unsigned_loc == 6'd48) ? 64'h0000_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd49) ? 64'h0001_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd50) ? 64'h0003_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd51) ? 64'h0007_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd52) ? 64'h000f_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd53) ? 64'h001f_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd54) ? 64'h003f_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd55) ? 64'h007f_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd56) ? 64'h00ff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd57) ? 64'h01ff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd58) ? 64'h03ff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd59) ? 64'h07ff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd60) ? 64'h0fff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd61) ? 64'h1fff_ffff_ffff_ffff :   
                          (in_unsigned_loc == 6'd62) ? 64'h3fff_ffff_ffff_ffff : 64'h7fff_ffff_ffff_ffff;
  `endif

  assign mantissa_int = in_unsigned & mantissa_mask;

  //1001 (9)
  //p = 3
  //m_mask = 0111


  // When in_unsigned_loc <= 52, then we have 52 bits or fewer in mantissa
  assign mantissa_trimmed_1 = mantissa_int[51:0];

  // when in_unsigned_loc > 52
  assign mantissa_trimmed_2_shift_amount = in_unsigned_loc - 6'd52;
  assign mantissa_trimmed_2_full = (mantissa_int >> mantissa_trimmed_2_shift_amount) + mantissa_trimmed_2_round_bit;
  assign mantissa_trimmed_2_round_bit = mantisRNŒÚwsh‘6        —Pë½D\x|^ù©ÀÑaµ^¦¥~Åqh\Ú)];@‹ü˜  @'ªÏÒôƒ‘žãñï6–áØ¤œµïæÐ"?l       @.¡Ö{‰¸ðæø”ÄíWuWæÐ°B‡ãµ<%ò+ŽCûÒNéÚÉ8 ZäÇ$   :Q}FÐFÓÆÙ%uêËÜvJ{®È>ë´"Ú”rg´öÝ\ Z$”       ¹D£~@×©±cqú’åWJ)¥’   f×ÂŒ àK§§y„n5~ý¡Ø’¶©3‹Ê-‰T¿Éª”Rjå       |j½‹C×¶â8¬Fõ°šRJ©•   ÌÎŒ èÂ.~µîÊOãIä›dÙªßdUJ)µò       >
µÞ…ü _â8¬Jõ°šRJ©•   ÌÎŒ èÂ>xŸéíÒ¾Ÿea/Ic‚X°ê7Y•RJ­¼       €B­wqaèÑ!)Ñ+ŽC×ª‡Õ”RJ­¼   `vfAûþŒßgú9ãòžƒk{û&yšqyÌ¬úMV¥”R+/       à£Pë]\ºóK‡UªVSJ)µò  €Ù™íkü>Ó}|yf-Xõ›¬J)¥V^       ÀG¡Ö»¸0tä°Ùlƒ%@‡Å¨VSJ)µò  €Ù™û¿Éô2û"wñî"KUý&«RJ©•       ðQ¨õ..½ø%ŽÃºU«)¥”Zy  ÀìÌ‚ÆEgïT¹NÇã†Ö9ÿ #æQý&«RJ©•       ðQ¨õ..íûOîŠã°<ÕÃjJ)¥V^   0;3‚ qÑAµfï„ùöe²­´NJ«~“U)¥ÔÊ       ø(Ôz†–6›çx¼øC…þshVõ°šRJ©•   ÌÎŒ h\èöÒc½uþîg©Uý&«RJ©•       ðQ¨õ..Í:]¡â8pR=¬¦”Rjå   ³3#Zö#x‘>W]í6²T3‚–ªúMV¥”R+/       à£Pë]\ôg¦lÍãÅÿŠãÐ»êa5¥”R+/   ˜AÐ²ç®®ÐÐŒ 7Ã–ªúMV¥”R+/       à£Pë½z¸çÞ®Ãñ5ÅqX†êa5¥”R+/   ˜AÐ²¾n/…&U_-…T¿Éª”Rjå      ÀT‡ÍæÛfó²Ù¼kû÷úþþïï7›»÷qëñíø–_Þw`h[Zj½‹p¸¸îÿ~9ü¾ø÷‡õ]'Cûsÿþ/_V¼9YäJÕìS_šU=¬¦”Rjå  Ð<M¿:mú™4…¦ßmš~Óí#WècíÕþåfµï°*¥”R       ¤8E„w›ÍÃñOéÒ«	¶Ëùøþþ^zððUžoÿ÷ÍyÛ™§cJ²¡Ö»¸ðæø‰ÿãïN¼z<^üÃùøµŽtì)%üøéä¿úu±?þÊÇ÷\5!Ã4§Oáç„×„f•K¡)¥”Rc
   Iš~·õÞô3#(JÓïKš~…fµp…†n†=Õ^-%T¹±ª”RJ      €˜×c–ëÔsÝSk§zü{Löµö;ÚSŒÛáú>úu¶Ú†B·ç	qŠû÷{ˆ¦ßnnà6) >´¼Ëº+±/ÁEN.\ž$û6.‡ÃÍ=®pû÷wº(.ÓÕ"¤ãM<'÷×þêBè Y¯¥”Rjb  4FÓï†Å4ýž‚+×ôK.M¿1›£é÷AwS¼BE&»‰_•J)¥ÔÄ      `¬BÛsæø®Æ›ú>"ñ|Jæý×Í×™½Zå¦XâóËFŸ†¬•"ÝÆãàã«bŒ~ä›óøÛŸe6ç¾øtoÊö>çxMhV¡/m¥”Rjd  4£ÐŸ{4ýnT¹¦_Âp§/?Á1¿l$M?M¿¡ÒôÛw¬…ñJÑ¯–§Ð·¥RJ)5²       øÂË{‚0cÀôj^¿\@öªo£ó‘C£3îÇFíI•&ýÐNYÞcÍ¹áåâ™3ÔÏyßÝfôžßÞövFhø†´-ÝßL‡^
š5Û··RJ)uµ   jÓô;ÕÂš~åÖœ°‡Ÿ…¶hNš~;M¿œ¾-¯~'¾´[0þçíM=Ô^-%Ìöµ©”RJ]-       ½T
•îf|¼èÄ¸ðÃ\²ÍýÆ«|¬]Ç…ÏAáÒ¹ùË:kÌó;s¹çCÛ>ó—ÆÌ» 	§Ù¿³¾&4k¶o'¥”Rêj  Ô£éwYkú™¥éw¹çš~Õ½½÷×÷úÇfóãx~n/Æíç½@nˆ^2,Òl_J)¥ÔÕ      àºZAásÍóT¹)qáýìÉÑŒáÈ*Ÿi¿qáóGPeßN5Ohxäž_ÝöÇßûY¶¥/¡Ý{÷|ÖÐ‡    @K4ý>ÔÂš~f…œ?‚ù7í\š~WKÓïƒÃ±î³ƒÆtófðüL        (îÏÙƒ°7ªtÜ--.|¨”Œ|«ß™Þx•O³Ç¸ð_Í\ûO–ýläžØöCÕmùQ~[ú2~÷ÆgÐC
     mÐô»Zkú™4’¦ßÕ=×ôc¼è        @YÛÚ™È«qÀrâÂ“‘§úgŽ7^eåÝÅ…ŸßÏÀºŸølïw3z
—ËháKcü©µ·÷êt>?e}Í    @Z¸ÿùu9«mú™4†¦ßÐ4ý¯©3        `íšŠEÎ ‹Æ…«g…O5=B]eÙ}Å…ŸkÊ7>ý—bïzäžŸ·½…¬pôìZ¼ÛŸ]ÚF…>     jÓôû²¥°˜¦ŸA_Òô»±çš~Œ´~Û˜        PÊ÷ÚQ¿/ó‘»2o||\øa³ù]{.uOÓÞx•e÷þÖptþTåÃ#÷ü´ííd…OU.EÝ—¡OííóºÏúšC    @=š~_ÖÂš~fÝ é÷åžkú1RhÖÖþxR        _ãYásŒlWà½¿¼§$³¼‘,5%WWåCì".<þ”¨[…Ã#÷|×Rzþ²’gà,ÉçÏkÊt «¯y»     ¨DÓoÌÖô3#hˆ¦ß˜=ßiú1Â!þ	ô        _¡¬ðþ½ò¾æ.÷Û™
M~#§„ñcŠñþð}9>4×æü3õ—øÐ¿¬öãÂ…²Â%.‡]™ÄðÈ=/ñv²ÔÄGí.Ãå†LŸôù5¿,     jÐô[gÓÏŒ «4ýFî¹¦cìâ         ™eÌ
Ÿ‚°÷›ÍëñŸOõýø¾æ‹`fO—ˆ‡žc”·£œ‡cí“u—õ;éç}¿c’£§_–}yãÂ¹N†Sšöñx¼¾ÇÄ·ÇOêt9<åËÚfOƒÏ–ó·Ä.÷5(1¼ßêŒB     ³Óô[mÓ/ã€M¿ÏKÒôûòlÑô[¼Cð<yÌ=ò        €ÿ˜˜Ò;EÇ§Çÿ}˜|Ðm¾È~{µ_ñeü÷´ƒÞ'½÷û‹Èæeâø6ðRÛ‹¤ì!²¶Ð†ç²üé?½oàç¼ø~ÚIXqÌøÏè=¼×Õ­8¿Löï±Ñäceü~èÔÕMž(ô)     0;M?M¿«M¿§à4ýN¥é7ôiú­Ð.þ9>×^3        ÀÒl'dòö‘XäUˆÿÈ´	yãÂûi{2%%™Wô]gŠ‡f11°»;žKÉþ5- û3Ó&lò]çJHÏo&?j·Ä9¹r¿Ž     øŠ¦ßFÓox%u,ã®é§é7Ï9IÈáýC¬ø=        °v/Ó"€¹LYÃøG™Þ1.œåA†ÉGÏ.cqá_IÑÆÝûÃ2³œŠ›ãóÓ>ýÇãÓL³Èr-œ*-(|ö-õCÙåÛ
ÎBû    ÀŒ4ýN4ý®ZÛŒ M¿³,×Â©4ýÖ,áS{®½f        €¥IŽ æJFž½LìNy~çI®¸ðï;ñÿI˜ø4Ó¢‡ÎnüÑ³Ä…w©§AöXê¯÷-­uN¿N‹Ï¥‘‡ìbó    Z•|G_Ó¯\¿å¤…¦ßÚfí4ýÞM¿4ý¸OúÈ~Ô^6        À¢lSóˆ©—¾'-æ1Çs4³Ä…3f…O’Ã¹Ô:nÂ¦Ç…ÓN€ÇÑù“äs²îCmÏ'ÃÄ'‰~Vq78m>     sÑô;Óô»jU3‚4ý.M¼4ý8$}dY†}        ðÿþHŠ î
¯*-1¼;>»nŠéqá‰’ÎøTÑèq³›-exŸtì‹e…OÒNËÇgã”kaWl[VRâ´\³Ðæ    0M¿Kš~W­gF¦ßS®…¦IV¹‰[         +•–,ô0ÑK	‰áýä´èÄ¸ð?ó¼õëþ¬‘¬žË
§xn5Ú˜vf>M¾T“¯…]Émù–´2²ó     íI»¯éwµ–Úô[ÏŒ M¿’¯…¦›Íö}¦\¨j/        `Qž'º›%+|ò’5›Rœ.-º¶\O4»ñGŸNxžèÛ¯ÿ‘í]~á÷í
-ïiÚA“¯…Òð|hïò\;    ÐM¿4ý¦WÓ¯M¿Kš~íK˜óv:sîk¯        `Q²\ÛyWøOOyÝ”¸ð<·mUUÏ‰Ž?ú”¸pÂóDg¡¦è§H»&>ØuŒÃìÉi.5{     ¬UÂí|M¿¡ZpÓo%3‚4ý>K»4ý87<áäy®½r        €¥	¥¸ö³¤ '.ò´Îo©ÇJŽÿÌùŽoy¦$³D$£ûŸÝ<AÕèGÿ4ããuÏžâ‰á)‘ñ„kaâÇ‹¦Øw³¬j%Bç     åE›9š~Cµì¦ßJfiú}–p-L<âxš~Í:¼_Œ	'         95›üàà"O^L“ž?E½.òuò£’]èÓOó3~šU¹îã§è”Ç '|KÌv9üW$9ýXéo;,Uè”      °„Ûùš~Ÿk
M¿5ÌÒô»*á[BÓèwÔe        S48%t8ÑS|µiÏzL{¤èÿf~»_Ø9ýƒíF§qáŽrÑGŠ>NˆŒG÷dæ'wV?3W«‹+    `5¢}M¿¡Z|Óo
3‚¢zÅV†¦_Úò4ýæ‘< è¹öÊ        (š´ûVuµÑüÙIGIˆ?e~££„9}…ÕC™ãžŽfp«<Oô,ú‰$(¡jN-¯mÙl;    @K¢}M¿«µ†¦ßfiúM?Ð©æÔòÚÖ)y@ÐCí•        ,P4Ëõ³ö‚£‰Õ´h`B\¸Jlt\dò%O¢áÔìÆ=-.ÝÏêÑÆh¸992ý¢H»î’E÷\l;    @3¢7ò5ý†j
M¿ÅÏÒôý¢H»î’iú5%y@ÐÛx¨½x        €ŠÆìÒžÐ™ÑÁo“Ž?m6wyßçhÑXÞÑä_vãžŽæ¡K¼Çû¹’²¡C<N>Ó¢¢9or±í     ÍÐô»JÓoú±4ýf éw¢é×ŽäA»ÉCÌ         ¸.”5|lãyo¡üÙ>)‚?ç—c…Ö9ñ˜ÑÏ.t®}ýÓ!ZH7&„2g8ÊÌÄ…k±í     ÍÐô»JÓoú±4ýæZsrïe†CL¡é×ˆ)‚^j/        `™î‚éÏFbv»HÊyŸôTÑh\¸âÎ„ß#¼¡
é1.}Žl¢IÙ´su†CLñÐöòÌ¶    ´á.ØÃiä®íNÓïÂœM¿ÅÏÒô2Ã!¦ÐôkA         -z&º~Ö^ðÉ]0´š[Æ…+Š¦EÿwÂ±Bê..Šœ¶“žßÌ’r}ôó©=R´Û    ÐM¿!š~W-{F¦ß
¡sLÓo…¦jdÜ        À2…2v›Í}íŸ…²hñ×Å…Óž^™ÑlÉ¼Ðº‹'„z¬lÚ²«ô·ýìóƒ[ Û    ÐM¿!š~W-{F¦ß
¡××ô[‚         ÚÕi8rS>Š?ç1¡­ØÎu îâÂý^åŸ€Úù)çX²N?»ÞÙv    €6ôÛåÐô»ÚŠ)
™eÏê÷rÐô­°©Ï®w‡÷=zùœÊ€         €âB¡Û*À!Ñ¸ðkðõCqáê‰·Ù>ÇÐžwî÷rˆÆ¸Äúè«h…‹dÛ    ÚÐo—CÓïÒlŸã²gõ{9húu±Âå1          ¡ðeS»ÿ	æ#£áÎñqáv&šÒ›ç@ÝÅ…C©Ç„×/*ôÑü,üúU´¿ÂE²í     mµ8šºe«éw)tß}Êj—=#HÓ/×ëWÑþ
æûñ7          i¯Á¤×KíJvF‚¡GŠV}Àj²ÐQº‹‡^¼©GŠn‚ç@ÑÍ©uE´¿ÂE²í     
Ðô»AÓïªeÏ
½¸¦_kWDû+\’ïÁ