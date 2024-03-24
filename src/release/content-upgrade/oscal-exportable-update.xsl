<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xpath-default-namespace="http://csrc.nist.gov/ns/oscal/1.0"
    xmlns="http://csrc.nist.gov/ns/oscal/1.0"
    version="3.0">
    <!-- Match any assembly called "exports" and reposition it one level up in the tree -->
    <xsl:template match="assembly[@name='exports']">
        <xsl:copy-of select="."/>
    </xsl:template>
    <!-- Prevent duplication of "exports" assembly by removing it from its original position -->
    <xsl:template match="control/assembly[@name='exports']"/>

</xsl:stylesheet>
