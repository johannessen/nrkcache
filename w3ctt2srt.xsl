<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:ttml="http://www.w3.org/ns/ttml"
                xmlns:tts="http://www.w3.org/2006/04/ttaf1#styling">
  <xsl:output
      method="text"
      indent = "no"
      encoding="UTF-8"/>

  <!--
      Usage:
      $ subsurl=$(curl "$showurl" | awk -F'"' '/data-subtitlesurl/ {print "http://tv.nrk.no"$2;exit}')
      $ curl "$subsurl" | xsltproc "$scriptdir/nrk-subtitles2srt.xsl" -
  -->


  <xsl:template match="ttml:tt">
    <xsl:apply-templates select="./ttml:body"/>
  </xsl:template>
  <xsl:template match="ttml:body">
    <xsl:apply-templates select="./*"/>
  </xsl:template>
  <xsl:template match="ttml:div">
    <xsl:apply-templates select="./*"/>
  </xsl:template>


  <xsl:template match="ttml:p">
    <!-- Weird indentation here because of literal newlines -->
    <xsl:number/><xsl:text>
</xsl:text>
    <xsl:call-template name="duration"/><xsl:text>
</xsl:text>
    <xsl:apply-templates/><xsl:text>

</xsl:text>
  </xsl:template>


  <xsl:template match="ttml:br">
    <xsl:text>
</xsl:text>
  </xsl:template>


  <xsl:template match="ttml:span">
    <xsl:text> </xsl:text>
    <xsl:choose>
      <xsl:when test="./@style='italic'">&lt;i&gt;<xsl:apply-templates select="*|text()"/>&lt;/i&gt;</xsl:when>
      <xsl:when test="./@style='bold'">&lt;b&gt;<xsl:apply-templates select="*|text()"/>&lt;/b&gt;</xsl:when>
      <xsl:otherwise>&lt;u&gt;<xsl:apply-templates select="*|text()"/>&lt;/u&gt;</xsl:otherwise>
    </xsl:choose>
    <xsl:text> </xsl:text>
  </xsl:template>


  
  <!-- That was the easy part, the mess below is all for creating the
       end-timestamp of each subtitle, since the XML format only
       specifies the start-timestamp -->

  <xsl:template name="duration">
    <xsl:variable name="nowsecs">
      <xsl:call-template name="fractions">
        <xsl:with-param name="timestring" select="./@begin"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="dursecs">
      <xsl:call-template name="fractions">
        <xsl:with-param name="timestring" select="./@dur"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="defsecs"><xsl:value-of select="$nowsecs + $dursecs"/></xsl:variable>

    <xsl:variable name="untilsecs">
      <xsl:variable name="nextsecs">
        <xsl:call-template name="fractions">
          <xsl:with-param name="timestring" select="following-sibling::ttml:p[1]/@begin"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:choose> <!-- even works for last item (no following-siblings and nextsecs is NaN) -->
        <xsl:when test="$nextsecs &lt; $defsecs"><xsl:value-of select="$nextsecs"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$defsecs"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    
    
    
    <xsl:variable name="nextff"><xsl:value-of select="format-number( $untilsecs mod 100, '00' )"/></xsl:variable>
    <xsl:variable name="nextss"><xsl:value-of select="format-number( (($untilsecs - $nextff) div 100) mod 60, '00' )"/></xsl:variable>
    <xsl:variable name="nextmm"><xsl:value-of select="format-number( (($untilsecs - $nextff - 60*$nextss) div 60 div 100) mod 60, '00' )"/></xsl:variable>
    <xsl:variable name="nexthh"><xsl:value-of select="format-number( (($untilsecs - $nextff - 60*$nextss - 3600*$nextmm) div 3600 div 100) mod 60, '00' )"/></xsl:variable>
 
<!--
    <xsl:variable name="nextss1"><xsl:value-of select="format-number( $untilsecs mod 60, '00' )"/></xsl:variable>
    <xsl:variable name="nextmm1"><xsl:value-of select="format-number( (($untilsecs - $nextss) div 60) mod 60, '00' )"/></xsl:variable>
    <xsl:variable name="nexthh1"><xsl:value-of select="format-number( ($untilsecs - $nextss - 60*$nextmm) div 3600, '00' )"/></xsl:variable>
-->

    <!-- Now output (we ignore milliseconds): -->
    <xsl:value-of select="translate(./@begin, '.', ',')"/> --&gt; <xsl:value-of select="concat($nexthh, ':', $nextmm, ':', $nextss, ',', $nextff, '0')"/> <!--(<xsl:value-of select="$nowsecs"/>-<xsl:value-of select="$dursecs"/>-<xsl:value-of select="$untilsecs"/>-<xsl:value-of select="$nextsecs"/>-<xsl:value-of select="$defsecs"/>)-->
  </xsl:template>

<!--
  <xsl:template name="seconds">
    <xsl:param name="timestring"/>
    <xsl:variable name="hh"><xsl:value-of select="substring($timestring, 1,2)"/></xsl:variable>
    <xsl:variable name="mm"><xsl:value-of select="substring($timestring, 4,2)"/></xsl:variable>
    <xsl:variable name="ss"><xsl:value-of select="substring($timestring, 7,2)"/></xsl:variable>
    <xsl:value-of select="$hh*3600+$mm*60+$ss"/>
  </xsl:template>
-->

  <xsl:template name="fractions">
    <xsl:param name="timestring"/>
    <xsl:variable name="hh"><xsl:value-of select="substring($timestring, 1,2)"/></xsl:variable>
    <xsl:variable name="mm"><xsl:value-of select="substring($timestring, 4,2)"/></xsl:variable>
    <xsl:variable name="ss"><xsl:value-of select="substring($timestring, 7,2)"/></xsl:variable>
    <xsl:variable name="ff"><xsl:value-of select="substring($timestring, 10,2)"/></xsl:variable>
    <xsl:value-of select="$hh*3600*100+$mm*60*100+$ss*100+$ff"/>
  </xsl:template>


</xsl:stylesheet>
