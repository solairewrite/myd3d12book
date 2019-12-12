cbuffer cbSsao : register(b0)
{
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gProjTex;
	float4   gOffsetVectors[14];

    // For SsaoBlur.hlsl
    float4 gBlurWeights[3];

    float2 gInvRenderTargetSize;

    // Coordinates given in view space.
	// �۲�ռ��еĸ�����
    float    gOcclusionRadius;
    float    gOcclusionFadeStart;
    float    gOcclusionFadeEnd;
    float    gSurfaceEpsilon;
};

cbuffer cbRootConstants : register(b1)
{
    bool gHorizontalBlur;
};
 
// Nonnumeric values cannot be added to a cbuffer.
// ����ֵ�����޷���ӵ�����������
Texture2D gNormalMap    : register(t0);
Texture2D gDepthMap     : register(t1);
Texture2D gRandomVecMap : register(t2);

SamplerState gsamPointClamp : register(s0);
SamplerState gsamLinearClamp : register(s1);
SamplerState gsamDepthMap : register(s2);
SamplerState gsamLinearWrap : register(s3);

static const int gSampleCount = 14;
 
// ��Ļ�������ǵ��uv
static const float2 gTexCoords[6] =
{
    float2(0.0f, 1.0f),
    float2(0.0f, 0.0f),
    float2(1.0f, 0.0f),
    float2(0.0f, 1.0f),
    float2(1.0f, 0.0f),
    float2(1.0f, 1.0f)
};
 
struct VertexOut
{
    float4 PosH : SV_POSITION;
    float3 PosV : POSITION; // �۲�ռ�,���ڽ�ƽ��ͶӰ������
	float2 TexC : TEXCOORD0;
};

VertexOut VS(uint vid : SV_VertexID)
{
    VertexOut vout;

    vout.TexC = gTexCoords[vid];

    // Quad covering screen in NDC space.
	// ����Ļ�ϵ�ȫ���ı���uv�任��NDC�ռ�����
    vout.PosH = float4(2.0f*vout.TexC.x - 1.0f, 1.0f - 2.0f*vout.TexC.y, 0.0f, 1.0f);
 
    // Transform quad corners to view space near plane.
	// ���ı��εĽǵ�任���۲�ռ��еĽ�ƽ����
    float4 ph = mul(vout.PosH, gInvProj);
    vout.PosV = ph.xyz / ph.w;

    return vout;
}

// ��ȡ����p����q�ڵ��̶�
float OcclusionFunction(float distZ)
{
	// ���depth(q)λ��depth(p)֮��(��������Χ),���q�޷��ڵ���p
	// ���depth(q)��depth(p)�������,Ҳ��Ϊ��q�����ڵ���p
	// ֻ�е�qλ�ڵ�p֮ǰ,�������û������Epsilonֵ����ȷ����q�Ե�p���ڱγ̶�
	
	float occlusion = 0.0f;
	if(distZ > gSurfaceEpsilon)
	{
		float fadeLength = gOcclusionFadeEnd - gOcclusionFadeStart;
		
		// Linearly decrease occlusion from 1 to 0 as distZ goes 
		// from gOcclusionFadeStart to gOcclusionFadeEnd.	
		// ����distZ��Startȡ��End,����ֵ��1������С��0
		occlusion = saturate( (gOcclusionFadeEnd-distZ)/fadeLength );
	}
	
	return occlusion;	
}

float NdcDepthToViewDepth(float z_ndc)
{
    // z_ndc = A + B/viewZ, where gProj[2,2]=A and gProj[3,2]=B.
    float viewZ = gProj[3][2] / (z_ndc - gProj[2][2]);
    return viewZ;
}
 
float4 PS(VertexOut pin) : SV_Target
{
	// p: Ҫ����Ļ������ڱ�Ŀ���
	// n: ��p���ķ�����
	// q: ���ƫ���p��һ��
	// r: �п����ڵ���p��һ��

	// ��ȡ����p�ڹ۲�ռ��еķ�����z����
    float3 n = normalize(gNormalMap.SampleLevel(gsamPointClamp, pin.TexC, 0.0f).xyz);
	// �����ͼ�л�ȡ��������NDC�ռ��ڵ�z����
    float pz = gDepthMap.SampleLevel(gsamDepthMap, pin.TexC, 0.0f).r;
    pz = NdcDepthToViewDepth(pz);

	// ���¹����۲�ռ�λ��
	float3 p = (pz/pin.PosV.z)*pin.PosV;
	
	// �������������ͼ����ȡ�������,��������[0,1]ӳ�䵽[-1,+1]
	// Ϊʲô*4?
	float3 randVec = 2.0f*gRandomVecMap.SampleLevel(gsamLinearWrap, 4.0f*pin.TexC, 0.0f).rgb - 1.0f;

	float occlusionSum = 0.0f;
	
	// Sample neighboring points about p in the hemisphere oriented by n.
	// ����pΪ���ĵİ�����,���ݷ���n��p��Χ�ĵ���в���
	for(int i = 0; i < gSampleCount; ++i)
	{
		// Are offset vectors are fixed and uniformly distributed (so that our offset vectors
		// do not clump in the same direction).  If we reflect them about a random vector
		// then we get a random uniform distribution of offset vectors.
		// ƫ���������ǹ̶��Ҿ��ȷֲ���
		// ��������ǹ���һ������������з���,��õ��ı�Ϊһ����ȷֲ������ƫ����
		float3 offset = reflect(gOffsetVectors[i].xyz, randVec);
	
		// Flip offset vector if it is behind the plane defined by (p, n).
		// �����ƫ������λ��(p,n)�������ƽ��֮��,�ͷ�ת(flip)��ƫ������
		// y=sign(x): x=0,y=0;x>0,y=1,x<0,y=-1
		float flip = sign( dot(offset, n) );
		
		// Sample a point near p within the occlusion radius.
		// ���ڱΰ뾶�ڲɼ�������p�ĵ�
		float3 q = p + flip * gOcclusionRadius * offset;
		
		// Project q and generate projective tex-coords.  
		// ͶӰ��q��������Ӧ��ͶӰ��������
		float4 projQ = mul(float4(q, 1.0f), gProjTex);
		projQ /= projQ.w;

		// ���Ŵӹ۲������q�ķ���,Ѱ����۲����������ֵ
		// ��ֵδ����q�����ֵ,��Ϊ��qֻ�ǽӽ��ڵ�p������һ��,��λ�ÿ��ܿ���һ��
		// Ϊ��,��Ҫ�鿴�˵������ͼ�е����ֵ
		float rz = gDepthMap.SampleLevel(gsamDepthMap, projQ.xy, 0.0f).r;
        rz = NdcDepthToViewDepth(rz);

		// ���¹����۲�ռ��е�λ������r
		float3 r = (rz / q.z) * q;

		// ���Ե�r�Ƿ��ڵ���p
		//	dot(n,normalize(r-p),����r����ƽ��(p,n)ǰ��ľ���
		//		Խ�����ڴ�ƽ���ǰ��,�͸����趨Խ����ڱ�Ȩ��
		//		(p,n)���ϵĵ�rû���ڵ���p
		//	����ڱε�r����Ŀ���p��Զ,����Ϊ��r�����ڵ��ڱε�p
		
		float distZ = p.z - r.z;
		float dp = max(dot(n, normalize(r - p)), 0.0f);

        float occlusion = dp*OcclusionFunction(distZ);

		occlusionSum += occlusion;
	}
	
	occlusionSum /= gSampleCount;
	
	float access = 1.0f - occlusionSum;

	// ��ǿSSAOͼ�ĶԱȶ�,ʹSSAOͼ��Ч����������
	return saturate(pow(access, 6.0f));
}
