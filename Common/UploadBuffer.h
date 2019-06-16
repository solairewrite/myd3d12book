#pragma once

#include "d3dUtil.h"

template<typename T>
class UploadBuffer
{
public:
	UploadBuffer(ID3D12Device* device, UINT elementCount, bool isConstantBuffer) :
		mIsConstantBuffer(isConstantBuffer)
	{
		mElementByteSize = sizeof(T);

		// Constant buffer elements need to be multiples of 256 bytes.
		// This is because the hardware can only view constant data 
		// at m*256 byte offsets and of n*256 byte lengths. 
		// typedef struct D3D12_CONSTANT_BUFFER_VIEW_DESC {
		// UINT64 OffsetInBytes; // multiple of 256
		// UINT   SizeInBytes;   // multiple of 256
		// } D3D12_CONSTANT_BUFFER_VIEW_DESC;
		// ������������Ӳ�����ر��Ҫ��,��С��ΪӲ����С����ռ�(256B)��������
		if (isConstantBuffer)
			mElementByteSize = d3dUtil::CalcConstantBufferByteSize(sizeof(T));

		ThrowIfFailed(device->CreateCommittedResource(
			&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD), // ����������ͨ����CPUÿ֡����һ��,���ϴ���
			D3D12_HEAP_FLAG_NONE,
			&CD3DX12_RESOURCE_DESC::Buffer(mElementByteSize*elementCount),
			D3D12_RESOURCE_STATE_GENERIC_READ,
			nullptr,
			IID_PPV_ARGS(&mUploadBuffer)));

		// ���ָ����������Դ���ݵ�ָ��
		// para1: ����Դ������,ָ������ӳ�������Դ.���ڻ�������˵,���������Ψһ������Դ,��Ϊ0
		// para2: �ڴ��ӳ�䷶Χ, nullptr��������Դ����ӳ��
		// para3: ��ӳ����Դ���ݵ�Ŀ���ڴ��
		ThrowIfFailed(mUploadBuffer->Map(0, nullptr, reinterpret_cast<void**>(&mMappedData)));

		// We do not need to unmap until we are done with the resource.  However, we must not write to
		// the resource while it is in use by the GPU (so we must use synchronization techniques).
	}

	UploadBuffer(const UploadBuffer& rhs) = delete;
	UploadBuffer& operator=(const UploadBuffer& rhs) = delete;
	~UploadBuffer()
	{
		// ������������������ɺ�,Ӧ�����ͷ�ӳ���ڴ�֮ǰ�������ȡ��ӳ�����
		// para1: ����Դ����,ָ���˽���ȡ��ӳ�������Դ,��������Ϊ0
		// para2: ȡ��ӳ����ڴ淶Χ, nullptrȡ��������Դ��ӳ��
		if (mUploadBuffer != nullptr)
			mUploadBuffer->Unmap(0, nullptr);

		mMappedData = nullptr;
	}

	ID3D12Resource* Resource()const
	{
		return mUploadBuffer.Get();
	}

	// ͨ��CPU�޸��ϴ�������������(eg, �۲����仯)
	void CopyData(int elementIndex, const T& data)
	{
		// �����ݴ�ϵͳ�ڴ渴�Ƶ�����������
		memcpy(&mMappedData[elementIndex*mElementByteSize], &data, sizeof(T));
	}

private:
	Microsoft::WRL::ComPtr<ID3D12Resource> mUploadBuffer;
	BYTE* mMappedData = nullptr;

	UINT mElementByteSize = 0;
	bool mIsConstantBuffer = false;
};